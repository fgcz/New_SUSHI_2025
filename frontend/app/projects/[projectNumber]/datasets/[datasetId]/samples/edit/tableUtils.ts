import { DatasetSample } from '@/lib/types';

export function extractUniqueColumns(samples: DatasetSample[]): string[] {
  return Array.from(new Set(samples.flatMap(sample => Object.keys(sample))));
}

export function isValidColumnName(columnName: string, existingColumns: string[]): boolean {
  return columnName.trim() !== '' && !existingColumns.includes(columnName.trim());
}
