import { useState, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { projectApi } from '@/lib/api';

const ALLOWED_EXTENSIONS = ['.txt', '.csv', '.tsv'];

interface UseImportDatasetFormParams {
  projectNumber: number;
  treeData: { tree: any[] } | undefined;
}

export function useImportDatasetForm({ projectNumber, treeData }: UseImportDatasetFormParams) {
  const router = useRouter();

  // Form state
  const [file, setFile] = useState<File | null>(null);
  const [datasetName, setDatasetName] = useState('');
  const [parentId, setParentId] = useState<number | null>(null);
  const [parentIdInput, setParentIdInput] = useState('');
  const [parentIdError, setParentIdError] = useState<string | null>(null);
  const [noParent, setNoParent] = useState(true);
  const [treeSearch, setTreeSearch] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isDragOver, setIsDragOver] = useState(false);

  // Build set of valid dataset IDs from tree
  const validIds = useMemo(() => {
    if (!treeData?.tree) return new Set<number>();
    return new Set(treeData.tree.map((node: any) => node.id));
  }, [treeData]);

  // File validation
  const isValidFileType = (fileName: string): boolean => {
    const lowerName = fileName.toLowerCase();
    return ALLOWED_EXTENSIONS.some(ext => lowerName.endsWith(ext));
  };

  // Process a file (shared by change and drop handlers)
  const processFile = (selectedFile: File) => {
    if (!isValidFileType(selectedFile.name)) {
      setError('Invalid file type. Please select a .txt, .csv, or .tsv file');
      return;
    }
    setError(null);
    setFile(selectedFile);
    if (!datasetName) {
      const nameWithoutExtension = selectedFile.name.replace(/\.(txt|csv|tsv)$/i, '');
      setDatasetName(nameWithoutExtension);
    }
  };

  // File input change handler
  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0];
    if (selectedFile) {
      processFile(selectedFile);
    }
  };

  // Drag and drop handlers
  const handleDragOver = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(true);
  };

  const handleDragLeave = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);
  };

  const handleDrop = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragOver(false);

    const droppedFile = e.dataTransfer.files?.[0];
    if (droppedFile) {
      processFile(droppedFile);
    }
  };

  // Parent ID input change with validation
  const handleParentIdChange = (value: string) => {
    setParentIdInput(value);
    setParentIdError(null);

    if (!value.trim()) {
      setParentId(null);
      return;
    }

    const numValue = parseInt(value, 10);
    if (isNaN(numValue)) {
      setParentIdError('Please enter a valid number');
      setParentId(null);
      return;
    }

    if (!validIds.has(numValue)) {
      setParentIdError(`Dataset #${numValue} not found`);
      setParentId(null);
      return;
    }

    setParentId(numValue);
  };

  // Selection from tree
  const handleTreeSelect = (id: number | null) => {
    setParentId(id);
    setParentIdInput(id?.toString() ?? '');
    setParentIdError(null);
  };

  // No parent checkbox handler
  const handleNoParentChange = (checked: boolean) => {
    setNoParent(checked);
    if (checked) {
      setParentId(null);
      setParentIdInput('');
      setParentIdError(null);
    }
  };

  // Form submission
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!file) {
      setError('Please select a dataset file');
      return;
    }

    if (!datasetName.trim()) {
      setError('Please enter a dataset name');
      return;
    }

    try {
      setIsSubmitting(true);
      await projectApi.importDataset(projectNumber, {
        file,
        name: datasetName.trim(),
        parentId: noParent ? null : parentId,
      });
      alert(`Dataset "${datasetName.trim()}" imported.`);
      router.push(`/projects/${projectNumber}/datasets`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Import failed');
    } finally {
      setIsSubmitting(false);
    }
  };

  return {
    // State
    file,
    datasetName,
    setDatasetName,
    parentId,
    parentIdInput,
    parentIdError,
    noParent,
    treeSearch,
    setTreeSearch,
    isSubmitting,
    error,
    isDragOver,

    // Handlers
    handleFileChange,
    handleDragOver,
    handleDragLeave,
    handleDrop,
    handleParentIdChange,
    handleTreeSelect,
    handleNoParentChange,
    handleSubmit,
  };
}
