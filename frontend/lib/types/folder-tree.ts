export interface FolderTreeNode {
  id: number;
  name: string;
  comment?: string;
  parent: number | "#";
}

export type FolderTreeResponse = FolderTreeNode[];