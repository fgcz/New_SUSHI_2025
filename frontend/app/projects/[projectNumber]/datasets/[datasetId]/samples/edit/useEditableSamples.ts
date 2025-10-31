import { useState, useCallback } from 'react';
import { DatasetSample } from '@/lib/types';
import {
  extractUniqueColumns,
  addColumnToSamples,
  removeColumnFromSamples,
  renameColumnInSamples,
  removeSampleRow,
  updateSampleCell,
  isValidColumnName
} from './tableUtils';

export interface UseEditableSamplesReturn {
  editableSamples: DatasetSample[];
  editableColumns: string[];
  newColumnName: string;
  setNewColumnName: (name: string) => void;
  initializeData: (samples: DatasetSample[]) => void;
  updateCell: (rowIndex: number, column: string, value: string) => void;
  removeRow: (rowIndex: number) => void;
  removeColumn: (columnIndex: number) => void;
  addColumn: () => void;
  renameColumn: (columnIndex: number, newName: string) => void;
}

export function useEditableSamples(): UseEditableSamplesReturn {
  const [editableSamples, setEditableSamples] = useState<DatasetSample[]>([]);
  const [editableColumns, setEditableColumns] = useState<string[]>([]);
  const [newColumnName, setNewColumnName] = useState('');

  const initializeData = useCallback((samples: DatasetSample[]) => {
    setEditableSamples(samples);
    const allColumns = extractUniqueColumns(samples);
    setEditableColumns(allColumns);
  }, []);

  const updateCell = useCallback((rowIndex: number, column: string, value: string) => {
    setEditableSamples(prev => updateSampleCell(prev, rowIndex, column, value));
  }, []);

  const removeRow = useCallback((rowIndex: number) => {
    setEditableSamples(prev => removeSampleRow(prev, rowIndex));
  }, []);

  const removeColumn = useCallback((columnIndex: number) => {
    const columnToRemove = editableColumns[columnIndex];
    setEditableColumns(prev => prev.filter((_, i) => i !== columnIndex));
    setEditableSamples(prev => removeColumnFromSamples(prev, columnToRemove));
  }, [editableColumns]);

  const addColumn = useCallback(() => {
    if (isValidColumnName(newColumnName, editableColumns)) {
      const trimmedName = newColumnName.trim();
      setEditableColumns(prev => [...prev, trimmedName]);
      setEditableSamples(prev => addColumnToSamples(prev, trimmedName));
      setNewColumnName('');
    }
  }, [newColumnName, editableColumns]);

  const renameColumn = useCallback((columnIndex: number, newName: string) => {
    const oldColumn = editableColumns[columnIndex];
    
    // Update column names
    const newColumns = [...editableColumns];
    newColumns[columnIndex] = newName;
    setEditableColumns(newColumns);
    
    // Update all samples to rename the column
    setEditableSamples(prev => renameColumnInSamples(prev, oldColumn, newName));
  }, [editableColumns]);

  return {
    editableSamples,
    editableColumns,
    newColumnName,
    setNewColumnName,
    initializeData,
    updateCell,
    removeRow,
    removeColumn,
    addColumn,
    renameColumn
  };
}