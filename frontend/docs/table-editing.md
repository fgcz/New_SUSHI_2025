# Table Editing System

This document explains the complete implementation of the editable table system used for sample data manipulation in datasets. It covers architecture, data flow, component interactions, and implementation details for developers.

## System Overview

The table editing system allows users to:
- **Edit cell values** in real-time
- **Add/remove columns** dynamically
- **Rename column headers** inline
- **Delete rows** of sample data
- **Validate inputs** before applying changes

### Architecture Components

```
SamplesEditPage
├── useDatasetBase (data fetching)
├── useDatasetSamples (samples data)
└── EditableTable
    ├── useEditableSamples (state management)
    └── tableUtils (pure functions)
```

## Information Flow

### 1. Data Loading Flow

```
User navigates to /samples/edit
       ↓
SamplesEditPage loads
       ↓
   ┌───────────────┬───────────────┐
   ↓               ↓               ↓
useDatasetBase  useDatasetSamples  UI Layout
fetches         fetches           renders
dataset info    sample data       skeleton
   ↓               ↓               ↓
Dataset info    EditableTable     Loading states
displayed       receives          handled
                initialSamples    
                   ↓
              useEditableSamples
              initializeData called
                   ↓
              extractUniqueColumns
              extracts column names
                   ↓
              State initialized with
              samples + columns
                   ↓
              Table renders with
              editable inputs
```

### 2. User Interaction Flow

```
User edits table
       ↓
   What action?
       ↓
┌──────┼──────┬──────┬──────┬──────┐
↓      ↓      ↓      ↓      ↓      ↓
Edit   Add    Remove Rename Delete 
cell   column column column row
↓      ↓      ↓      ↓      ↓
updateCell  addColumn  removeColumn  renameColumn  removeRow
called      called     called        called        called
↓      ↓      ↓      ↓      ↓
updateSampleCell    addColumnToSamples    removeColumnFromSamples    renameColumnInSamples    removeSampleRow
utility             utility               utility                    utility                  utility
↓      ↓      ↓      ↓      ↓
└──────┼──────┴──────┴──────┘
       ↓
   State updated
       ↓
   Table re-renders
```

## Component Architecture

### SamplesEditPage (`page.tsx`)

**Responsibilities:**
- Route parameter extraction
- Data fetching coordination
- Loading/error state management
- Page layout and navigation

```tsx
export default function SamplesEditPage() {
  const { dataset, isLoading, error, notFound } = useDatasetBase(projectNumber, datasetId);
  const { samples, isLoading: samplesLoading, error: samplesError } = useDatasetSamples(datasetId);
  
  // Handles loading states, errors, and renders EditableTable
}
```

**Key Features:**
- Uses existing hooks for consistency
- Proper error boundaries
- Loading skeleton extraction
- Breadcrumb navigation

### EditableTable Component

**Responsibilities:**
- Table UI rendering
- User interaction handling
- Local state management delegation

```tsx
export default function EditableTable({ initialSamples, projectNumber, datasetId }) {
  const {
    editableSamples,
    editableColumns,
    updateCell,
    removeRow,
    // ... other operations
  } = useEditableSamples();
  
  // Renders table with input fields and action buttons
}
```

**Key Features:**
- **Editable headers**: Click to rename columns
- **Editable cells**: Direct input modification
- **Dynamic columns**: Add/remove columns on demand
- **Row operations**: Delete rows with confirmation
- **Real-time updates**: Immediate visual feedback

## State Management: useEditableSamples Hook

### State Structure

```tsx
interface State {
  editableSamples: DatasetSample[];    // Current table data
  editableColumns: string[];           // Column order and names
  newColumnName: string;               // Input for adding columns
}
```

### Core Operations

#### 1. Data Initialization
```tsx
const initializeData = useCallback((samples: DatasetSample[]) => {
  setEditableSamples(samples);
  const allColumns = extractUniqueColumns(samples);
  setEditableColumns(allColumns);
}, []);
```

**Process:**
1. Receives raw sample data from API
2. Extracts unique column names across all samples
3. Initializes editable state with clean data structure

#### 2. Cell Updates
```tsx
const updateCell = useCallback((rowIndex: number, column: string, value: string) => {
  setEditableSamples(prev => updateSampleCell(prev, rowIndex, column, value));
}, []);
```

**Process:**
1. User types in input field
2. `onChange` event triggers `updateCell`
3. `updateSampleCell` utility creates new state
4. React re-renders affected cell

#### 3. Column Operations

**Adding Columns:**
```tsx
const addColumn = useCallback(() => {
  if (isValidColumnName(newColumnName, editableColumns)) {
    setEditableColumns(prev => [...prev, trimmedName]);
    setEditableSamples(prev => addColumnToSamples(prev, trimmedName));
    setNewColumnName('');
  }
}, [newColumnName, editableColumns]);
```

**Removing Columns:**
```tsx
const removeColumn = useCallback((columnIndex: number) => {
  const columnToRemove = editableColumns[columnIndex];
  setEditableColumns(prev => prev.filter((_, i) => i !== columnIndex));
  setEditableSamples(prev => removeColumnFromSamples(prev, columnToRemove));
}, [editableColumns]);
```

**Renaming Columns:**
```tsx
const renameColumn = useCallback((columnIndex: number, newName: string) => {
  const oldColumn = editableColumns[columnIndex];
  // Update column array
  const newColumns = [...editableColumns];
  newColumns[columnIndex] = newName;
  setEditableColumns(newColumns);
  // Update all sample data
  setEditableSamples(prev => renameColumnInSamples(prev, oldColumn, newName));
}, [editableColumns]);
```

## Utility Functions (tableUtils.ts)

### Pure Functions Design

All table operations are implemented as **pure functions** that:
- Take current state as input
- Return new state without mutations
- Are easily testable in isolation
- Follow functional programming principles

### Key Utilities

#### extractUniqueColumns
```tsx
export function extractUniqueColumns(samples: DatasetSample[]): string[] {
  return Array.from(new Set(samples.flatMap(sample => Object.keys(sample))));
}
```
**Purpose:** Extract all unique column names from heterogeneous sample data.

#### updateSampleCell
```tsx
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
```
**Purpose:** Immutably update a single cell value.

#### Column Management Functions
- **`addColumnToSamples`**: Adds new column with empty values to all rows
- **`removeColumnFromSamples`**: Removes column from all rows
- **`renameColumnInSamples`**: Renames column keys across all samples
- **`removeSampleRow`**: Filters out specific row by index

#### Validation
```tsx
export function isValidColumnName(columnName: string, existingColumns: string[]): boolean {
  return columnName.trim() !== '' && !existingColumns.includes(columnName.trim());
}
```
**Purpose:** Prevent duplicate or empty column names.

## Data Types

### DatasetSample Interface
```tsx
interface DatasetSample {
  id: number;
  [key: string]: any;  // Dynamic columns
}
```

**Characteristics:**
- **Dynamic schema**: Samples can have different column sets
- **String keys**: Column names are string identifiers
- **Mixed values**: Cell values can be strings, numbers, etc.
- **ID requirement**: Each sample has unique identifier

## User Experience Features

### Real-time Editing
- **Immediate feedback**: Changes appear instantly
- **No save required**: Edits persist in local state
- **Undo capability**: Pure functions enable easy rollback

### Column Management
- **Inline renaming**: Click header to edit column name
- **Visual feedback**: Hover states and focus indicators
- **Add columns**: Input field in header with validation
- **Remove columns**: × button with confirmation

### Row Operations
- **Delete rows**: Per-row delete button
- **Visual confirmation**: Color changes on hover
- **Keyboard support**: Tab navigation through inputs

### Error Handling
- **Loading states**: Skeleton placeholders during data fetch
- **Error boundaries**: Graceful failure display
- **Validation feedback**: Invalid column names rejected
- **Empty states**: Helpful messaging when no data

## Performance Considerations

### Optimizations Applied

1. **useCallback**: All handler functions memoized
2. **Pure functions**: Enables React optimization
3. **Immutable updates**: Proper React state management
4. **Key props**: Stable keys for list rendering

### Potential Improvements

1. **Virtualization**: For large datasets (1000+ rows)
2. **Debounced saves**: Reduce API calls on rapid edits
3. **Field validation**: Real-time input validation
4. **Undo/redo stack**: More sophisticated history management

## Integration Patterns

### Hook Integration
```tsx
// Existing hooks used for consistency
const { dataset } = useDatasetBase(projectNumber, datasetId);
const { samples } = useDatasetSamples(datasetId);

// Custom hook for table-specific logic
const { editableSamples, updateCell } = useEditableSamples();
```

### Data Flow Integration
```tsx
// Page → Table → Hook → Utils → State
SamplesEditPage
  ↓ (passes initialSamples)
EditableTable
  ↓ (calls operations)
useEditableSamples
  ↓ (calls pure functions)
tableUtils
  ↓ (returns new state)
React State Update
```

## Testing Strategy

### Unit Tests
- **tableUtils**: Test all pure functions in isolation
- **Hook logic**: Test state transitions
- **Validation**: Test column name validation rules

### Integration Tests
- **Component interaction**: User clicks and typing
- **Data flow**: End-to-end editing scenarios
- **Error states**: Invalid inputs and edge cases

### Example Test Cases
```tsx
describe('updateSampleCell', () => {
  it('should update specific cell without mutating original', () => {
    const samples = [{ id: 1, name: 'test' }];
    const result = updateSampleCell(samples, 0, 'name', 'updated');
    expect(result[0].name).toBe('updated');
    expect(samples[0].name).toBe('test'); // Original unchanged
  });
});
```

## Future Enhancements

### Immediate Improvements
1. **API Integration**: Save changes to backend
2. **Bulk operations**: Select multiple rows/columns
3. **Import/export**: CSV/Excel integration
4. **Data validation**: Type checking and constraints

### Advanced Features
1. **Collaborative editing**: Real-time multi-user editing
2. **Version history**: Track changes over time
3. **Cell formulas**: Excel-like calculations
4. **Data filtering**: Advanced search and filter options

## Conclusion

The table editing system demonstrates **clean architecture principles**:

- **Separation of concerns**: UI, state, and business logic separated
- **Pure functions**: Predictable, testable operations
- **Hook patterns**: Consistent with React best practices
- **Type safety**: Full TypeScript integration

This architecture enables **maintainable**, **testable**, and **extensible** table editing functionality that integrates seamlessly with the broader application architecture.