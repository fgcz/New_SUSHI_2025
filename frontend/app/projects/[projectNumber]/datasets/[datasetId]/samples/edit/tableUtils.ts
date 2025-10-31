import { DatasetSample } from '@/lib/types';

/**
 * Extract unique column names from an array of samples
 */
export function extractUniqueColumns(samples: DatasetSample[]): string[] {
  return Array.from(new Set(samples.flatMap(sample => Object.keys(sample))));
}

/**
 * Add a new column to all samples with empty string value
 */
export function addColumnToSamples(samples: DatasetSample[], columnName: string): DatasetSample[] {
  return samples.map(sample => ({
    ...sample,
    [columnName]: ''
  }));
}

/**
 * Remove a column from all samples
 */
export function removeColumnFromSamples(samples: DatasetSample[], columnName: string): DatasetSample[] {
  return samples.map(sample => {
    const newSample = { ...sample };
    delete newSample[columnName];
    return newSample;
  });
}

/**
 * Rename a column in all samples
 */
export function renameColumnInSamples(samples: DatasetSample[], oldName: string, newName: string): DatasetSample[] {
  return samples.map(sample => {
    const newSample = { ...sample };
    if (oldName in newSample) {
      newSample[newName] = newSample[oldName];
      delete newSample[oldName];
    }
    return newSample;
  });
}

/**
 * Remove a sample row by index
 */
export function removeSampleRow(samples: DatasetSample[], index: number): DatasetSample[] {
  return samples.filter((_, i) => i !== index);
}

/**
 * Update a specific cell value in the samples
 */
export function updateSampleCell(
  samples: DatasetSample[], 
  rowIndex: number, 
  column: string, 
  value: string
): DatasetSample[] {
  const updatedSamples = [...samples];
  updatedSamples[rowIndex] = {
    ...updatedSamples[rowIndex],
    [column]: value
  };
  return updatedSamples;
}

/**
 * Validate if a column name is valid (non-empty and unique)
 */
export function isValidColumnName(columnName: string, existingColumns: string[]): boolean {
  return columnName.trim() !== '' && !existingColumns.includes(columnName.trim());
}