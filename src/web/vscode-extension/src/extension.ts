import * as vscode from "vscode";
import WAForth, { ErrorCode, isSuccess } from "../../waforth";
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
        let outputBuffer: string[] = [];
        const flushOutputBuffer = () => {
          if (outputBuffer.length === 0) {
            return;
          }
          execution.appendOutput(
            new vscode.NotebookCellOutput([
              vscode.NotebookCellOutputItem.text(outputBuffer.join("")),
            ])
          );
          outputBuffer = [];
        };
        const emit = (c: string) => {
          outputBuffer.push(c);
          if (c.endsWith("\n")) {
            flushOutputBuffer();
          }
        };

        let result: ErrorCode;
        const program = execution.cell.document.getText();
        if (cell.document.languageId != "waforth") {
          throw new Error("can't happen");
        }
        if (!turtleSupport) {
          const forth = stateful ? globalForth : await new WAForth().load();
          forth.onEmit = emit;
          result = forth.interpret(program, true);
        } else {
          const jsx = new JSJSX();
          const svgEl = jsx.createElement("svg", {
            xmlns: "http://www.w3.org/2000/svg",
          });
          result = (await draw({
            program,
            drawEl: svgEl as any,
            onEmit: emit,
            showTurtle: true,
            jsx,
          }))!;
          const paths = (svgEl._children as any[]).find(
            (el) => el._tag === "g"
          )._children;
          if (paths.length > 1 || paths[0].d !== "M0 0") {
            svgEl.height = "300px";
            svgEl.style =
              "background-color: rgb(221, 248, 221); border-radius: 10px;";
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
        flushOutputBuffer();
        execution.end(isSuccess(result), Date.now());
      } catch (e) {
        vscode.window.showErrorMessage((e as any).message);
        execution.end(false, Date.now());
      }
    }
  };
}
