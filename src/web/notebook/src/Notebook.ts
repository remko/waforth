export type Notebook = {
  cells: NotebookCell[];
};

export type NotebookCell = {
  language: string;
  value: string;
  kind: number;
  editable?: boolean;
};

export function parseNotebook(contents: string): Notebook {
  if (contents.trim().length === 0) {
    return { cells: [] };
  }
  return JSON.parse(contents);
}

export function serializeNotebook(notebook: Notebook) {
  return JSON.stringify(notebook, undefined, 2);
}
