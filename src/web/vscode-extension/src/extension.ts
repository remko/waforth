import * as vscode from "vscode";
import WAForth, { ErrorCode, isSuccess, withLineBuffer } from "../../waforth";
import draw from "../../thurtle/draw";
import JSJSX from "thurtle/jsjsx";
import {
  parseNotebook,
  Notebook,
  serializeNotebook,
} from "../../notebook/src/Notebook";

export async function activate(context: vscode.ExtensionContext) {
  context.subscriptions.push(
    vscode.workspace.registerNotebookSerializer(
      "waforth-notebook",
      new NotebookSerializer(),
      {
        transientOutputs: true,
      }
    )
  );
  await createNotebookController("WAForth", "waforth-controller", false, false);
  await createNotebookController("Thurtle", "thurtle-controller", true, false);

  context.subscriptions.push(
    vscode.commands.registerCommand("waforth-notebook.new", async function () {
      const newNotebook = await vscode.workspace.openNotebookDocument(
        "waforth-notebook",
        new vscode.NotebookData([
          new vscode.NotebookCellData(
            vscode.NotebookCellKind.Code,
            ".( Hello world) CR",
            "waforth"
          ),
        ])
      );
      await vscode.commands.executeCommand("vscode.open", newNotebook.uri);
    })
  );
}

export function deactivate() {
  // do nothing
}

//////////////////////////////////////////////////
// Notebook Serializer
//////////////////////////////////////////////////

export class NotebookSerializer implements vscode.NotebookSerializer {
  public readonly label: string = "WAForth Content Serializer";

  public async deserializeNotebook(
    data: Uint8Array
  ): Promise<vscode.NotebookData> {
    let raw: Notebook;
    try {
      raw = parseNotebook(new TextDecoder().decode(data));
    } catch (e) {
      vscode.window.showErrorMessage("Error parsing:", (e as any).message);
      raw = { cells: [] };
    }
    const cells = raw.cells.map(
      (item) =>
        new vscode.NotebookCellData(item.kind, item.value, item.language)
    );
    return new vscode.NotebookData(cells);
  }

  public async serializeNotebook(
    data: vscode.NotebookData
  ): Promise<Uint8Array> {
    const contents: Notebook = { cells: [] };
    for (const cell of data.cells) {
      contents.cells.push({
        kind: cell.kind,
        language: cell.languageId,
        value: cell.value,
      });
    }
    return new TextEncoder().encode(serializeNotebook(contents));
  }
}

//////////////////////////////////////////////////
// Notebook Controller
//////////////////////////////////////////////////

async function createNotebookController(
  name: string,
  id: string,
  turtleSupport: boolean,
  stateful: boolean
) {
  let executionOrder = 0;

  // Global instance (for non-Thurtle kernel)
  let globalForth: WAForth;
  if (stateful) {
    globalForth = await new WAForth().load();
  }

  const controller = vscode.notebooks.createNotebookController(
    id,
    "waforth-notebook",
    name
  );
  controller.supportedLanguages = ["waforth"];
  controller.supportsExecutionOrder = stateful;
  controller.executeHandler = async (
    cells: vscode.NotebookCell[],
    _notebook: vscode.NotebookDocument,
    controller: vscode.NotebookController
  ) => {
    for (const cell of cells) {
      const execution = controller.createNotebookCellExecution(cell);
      execution.executionOrder = ++executionOrder;
      execution.start(Date.now());
      execution.clearOutput();
      try {
        const output = (line: string) => {
          execution.appendOutput(
            new vscode.NotebookCellOutput([
              vscode.NotebookCellOutputItem.text(line),
            ])
          );
        };

        let result: ErrorCode;
        const program = execution.cell.document.getText();
        if (cell.document.languageId != "waforth") {
          throw new Error("can't happen");
        }
        if (!turtleSupport) {
          const forth = stateful ? globalForth : await new WAForth().load();
          forth.onEmit = withLineBuffer(output);
          result = forth.interpret(program, true);
        } else {
          const jsx = new JSJSX();
          const svgEl = jsx.createElement("svg", {
            xmlns: "http://www.w3.org/2000/svg",
          });
          const drawResult = (await draw({
            program,
            drawEl: svgEl as any,
            onEmit: output,
            showTurtle: true,
            jsx,
          }))!;
          result = drawResult.result;
          if (!drawResult.isEmpty) {
            svgEl.height = "300px";
            svgEl.style =
              "background-color: rgb(221, 248, 221); border: thin solid rgb(171, 208, 166); border-radius: 10px;";
            execution.appendOutput(
              new vscode.NotebookCellOutput([
                vscode.NotebookCellOutputItem.text(
                  "<div style='width: 100%; display: flex; justify-content: center;'>" +
                    jsx.toHTML(svgEl) +
                    "</div>",
                  "text/html"
                ),
              ])
            );
          }
        }
        execution.end(isSuccess(result), Date.now());
      } catch (e) {
        vscode.window.showErrorMessage((e as any).message);
        execution.end(false, Date.now());
      }
    }
  };
}
