# Props Immutability in React

## Overview
This document explains why React props should never be mutated and how to properly handle data that needs to be edited, particularly in the context of our editable table components.

## Why Separate `editableSamples` from `initialSamples`?

### 1. React Props are Immutable

```tsx
// This is WRONG - you cannot mutate props
function EditableTable({ initialSamples }) {
  initialSamples[0].name = "changed"; // ❌ Mutating props = React violation
  return <HotTable data={initialSamples} />
}
```

**React Principle**: Props are read-only and should never be modified directly by child components.

### 2. Parent Component Owns the Source Data

- `initialSamples` belongs to the parent (comes from `useDatasetSamples`)
- Parent might re-fetch, update, or replace this data
- Child component shouldn't modify parent's data directly
- Parent maintains control over the source of truth

### 3. Local State for Edits

```tsx
// ✅ Correct pattern:
const [editableSamples, setEditableSamples] = useState([]);

// Copy parent data to local state for editing
useEffect(() => {
  if (initialSamples.length > 0) {
    initializeData(initialSamples); // Creates local copy
  }
}, [initialSamples]);
```

## Handsontable (HOT) Integration Patterns

### Current Implementation

```tsx
<HotTable
  data={editableSamples.map(sample => 
    editableColumns.map(column => sample[column] || '')
  )}
  // ... other props
/>
```

### HOT's Behavior

1. **Read-only by default**: HOT receives a **transformed copy** of the data
2. **No direct mutation**: The `.map()` creates a new 2D array
3. **Change callbacks**: HOT fires events when user edits cells

### Enabling Controlled In-Place Editing

```tsx
<HotTable
  data={editableSamples} // Direct reference
  afterChange={(changes) => {
    // Handle changes manually
    if (changes) {
      const newSamples = [...editableSamples];
      changes.forEach(([row, col, oldVal, newVal]) => {
        newSamples[row][col] = newVal;
      });
      setEditableSamples(newSamples);
    }
  }}
/>
```

## Why Never Mutate Props In-Place

### The Wrong Way

```tsx
// ❌ DON'T DO THIS
function EditableTable({ initialSamples }) {
  const handleEdit = () => {
    initialSamples[0].name = "changed"; // Mutates parent's data!
    // Parent component has no idea data changed
    // React won't re-render
    // State becomes inconsistent
  };
}
```

### Problems with Prop Mutation

1. **Breaks React's unidirectional data flow**
   - Data should flow down, events should flow up
   - Mutations bypass React's state management

2. **Parent loses control** over its own data
   - Parent can't track changes
   - Can't implement undo/redo functionality
   - Difficult to sync with backend

3. **No re-renders triggered** - UI becomes stale
   - React doesn't detect mutations
   - Component won't update when it should

4. **Debugging nightmare** - mutations are invisible
   - React DevTools won't show the changes
   - Hard to trace where data was modified

5. **Breaks time-travel debugging** and React DevTools
   - State history becomes corrupted
   - Debugging tools can't track mutations

## The Correct Data Flow Pattern

### Architecture

```
Parent Component (source of truth)
   ↓ initialSamples (props)
Child Component (local editing state)
   ↓ editableSamples (state)
HOT Table (UI)
   ↓ user edits
Change Callbacks
   ↓ update editableSamples (setState)
Save Action
   ↓ send changes back to parent (callback prop)
Parent Updates
   ↓ new initialSamples (props)
```

### Implementation Example

```tsx
// Parent Component
function DatasetPage() {
  const [samples, setSamples] = useState([]);
  
  const handleSaveChanges = (editedSamples) => {
    // Validate and save changes
    setSamples(editedSamples);
    // Send to backend...
  };

  return (
    <EditableTable 
      initialSamples={samples}
      onSave={handleSaveChanges}
    />
  );
}

// Child Component
function EditableTable({ initialSamples, onSave }) {
  const [editableSamples, setEditableSamples] = useState([]);
  
  // Sync with parent data
  useEffect(() => {
    if (initialSamples.length > 0) {
      setEditableSamples([...initialSamples]); // Create copy
    }
  }, [initialSamples]);

  const handleSave = () => {
    onSave(editableSamples); // Send changes back up
  };

  const handleCancel = () => {
    setEditableSamples([...initialSamples]); // Reset to original
  };

  return (
    <div>
      <HotTable data={editableSamples} />
      <button onClick={handleSave}>Save</button>
      <button onClick={handleCancel}>Cancel</button>
    </div>
  );
}
```

## Benefits of This Pattern

### 1. Isolation
- Edits don't affect parent until explicitly saved
- Multiple edit sessions can coexist
- Changes can be validated before committing

### 2. Cancel Capability
- Can discard changes easily
- Return to original state anytime
- Implement undo/redo functionality

### 3. Validation
- Validate data before committing changes
- Show errors without affecting source data
- Prevent invalid data from propagating

### 4. Re-fetchable
- Parent can refresh data independently
- Handle concurrent edits gracefully
- Sync with real-time updates

### 5. React Compliant
- Follows React's unidirectional data flow
- Leverages React's optimization strategies
- Compatible with React DevTools and debugging

## Common Pitfalls to Avoid

### 1. Shallow Copy Issues
```tsx
// ❌ Shallow copy - nested objects still shared
const editableSamples = [...initialSamples];
editableSamples[0].name = "changed"; // Still mutates original!

// ✅ Deep copy for nested objects
const editableSamples = initialSamples.map(sample => ({...sample}));
```

### 2. Direct Array Methods
```tsx
// ❌ Mutating methods
editableSamples.push(newItem);
editableSamples.splice(0, 1);

// ✅ Immutable updates
setEditableSamples([...editableSamples, newItem]);
setEditableSamples(editableSamples.filter((_, i) => i !== 0));
```

### 3. Missing Dependencies
```tsx
// ❌ Missing initialSamples dependency
useEffect(() => {
  setEditableSamples(initialSamples);
}, []); // Won't update when initialSamples changes

// ✅ Include all dependencies
useEffect(() => {
  if (initialSamples.length > 0) {
    setEditableSamples([...initialSamples]);
  }
}, [initialSamples]);
```

## Best Practices

1. **Always copy props to local state** for editing
2. **Use immutable update patterns** with setState
3. **Provide save/cancel functionality** for user control
4. **Validate data** before propagating changes
5. **Use callback props** to communicate changes back to parent
6. **Deep copy nested objects** when necessary
7. **Handle loading states** appropriately during data sync

## Summary

Props immutability is fundamental to React's predictable state management. By maintaining separate local state for edits and using proper data flow patterns, we ensure:

- **Predictable behavior**: Changes are tracked and controlled
- **Better debugging**: Clear data flow and state transitions
- **Enhanced UX**: Save/cancel functionality and validation
- **Maintainable code**: Follows React best practices

Never mutate props directly - always copy to local state for editing operations.