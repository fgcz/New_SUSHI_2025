import { useEffect, useRef, useMemo } from 'react';
import { DatasetSample } from '@/lib/types';
import { registerAllModules } from 'handsontable/registry';
import { HotTable } from '@handsontable/react-wrapper';
import 'handsontable/dist/handsontable.full.min.css';
import 'handsontable/styles/ht-theme-classic.css';

interface EditableTableProps {
  initialSamples: DatasetSample[];
}

export default function EditableTable({ 
  initialSamples, 
}: EditableTableProps) {

  const hotTableRef = useRef<any>(null);

  useEffect(() => {
    registerAllModules();
  }, [])


  const { tableData, columns } = useMemo(() => {
    if (!initialSamples || initialSamples.length === 0) {
      return { tableData: [], columns: [] };
    }

    const cols = Array.from(
      new Set(initialSamples.flatMap(sample => Object.keys(sample)))
    );

    // Create table data: headers as first row, then sample data
    const data = [
      cols, // Header row
      ...initialSamples.map(sample => 
        cols.map(column => sample[column] || '')
      )
    ];

    return { tableData: data, columns: cols };
  }, [initialSamples]);

  const handleSaveChanges = () => {
    if (hotTableRef.current) {
      const hotInstance = hotTableRef.current.hotInstance;
      const data = hotInstance.getData();
      console.log('HOT Table Data:', data);
      
      if (data && data.length > 0) {
        // First row contains the headers
        const headers = data[0];
        // Rest of the rows contain the actual data
        const dataRows = data.slice(1);
        
        console.log('Headers:', headers);
        console.log('Data Rows:', dataRows);
        
        // Convert back to object format using editable headers
        const convertedData = dataRows.map((row: any[]) => {
          const obj: any = {};
          headers.forEach((header: string, index: number) => {
            obj[header || `Column ${index + 1}`] = row[index] || '';
          });
          return obj;
        });
        console.log('Converted Data:', convertedData);
      }
    }
  };

  // TODO, move this into the loading of samples/edit page, and not here.
  // if (isLoading && !initialSamples.length) {
  //   return (
  //     <div className="animate-pulse">
  //       <div className="bg-gray-200 rounded-lg">
  //         <div className="px-4 py-3 bg-gray-100 border-b">
  //           <div className="flex space-x-4">
  //             <div className="h-4 bg-gray-300 rounded w-16"></div>
  //             <div className="h-4 bg-gray-300 rounded w-24"></div>
  //             <div className="h-4 bg-gray-300 rounded w-20"></div>
  //             <div className="h-4 bg-gray-300 rounded w-32"></div>
  //             <div className="h-4 bg-gray-300 rounded w-16"></div>
  //           </div>
  //         </div>
  //         {[...Array(3)].map((_, i) => (
  //           <div key={i} className="px-4 py-3 border-b">
  //             <div className="flex space-x-4">
  //               <div className="h-8 bg-gray-200 rounded w-16"></div>
  //               <div className="h-8 bg-gray-200 rounded w-24"></div>
  //               <div className="h-8 bg-gray-200 rounded w-20"></div>
  //               <div className="h-8 bg-gray-200 rounded w-32"></div>
  //               <div className="h-6 bg-gray-200 rounded w-12"></div>
  //             </div>
  //           </div>
  //         ))}
  //       </div>
        
  //       {/* Action buttons skeleton */}
  //       <div className="mt-4 flex justify-end items-center space-x-2">
  //         <div className="h-8 bg-gray-200 rounded w-16"></div>
  //         <div className="h-8 bg-gray-200 rounded w-24"></div>
  //       </div>
  //     </div>
  //   );
  // }

  if (!initialSamples.length) {
    return (
      <div className="text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300">
        <div className="text-gray-400 text-lg mb-2">📊</div>
        <h4 className="text-lg font-medium text-gray-900 mb-2">No samples found</h4>
        <p className="text-gray-500 text-sm mb-4">This dataset doesn't contain any sample data yet.</p>
        <p className="text-gray-400 text-sm">No samples available to edit.</p>
      </div>
    );
  }

  return (
    <div className="w-full">
      <div className="mb-6 border border-gray-200 rounded-lg overflow-hidden">
        <HotTable
          ref={hotTableRef}
          data={tableData}
          colHeaders={false}
          rowHeaders={true}
          width="100%"
          height={400}
          colWidths={200}
          columnSorting={false}
          themeName="ht-theme-classic"
          contextMenu={{
            items: {
              'row_above': {
                name: 'Insert row above',
                disabled: function() {
                  if (hotTableRef.current) {
                    const selected = hotTableRef.current.hotInstance.getSelected();
                    if (selected && selected[0]) {
                      return selected[0][0] === 0; // Disable if first row selected
                    }
                  }
                  return false;
                }
              },
              'row_below': {
                name: 'Insert row below'
              },
              'col_left': {
                name: 'Insert column left'
              },
              'col_right': {
                name: 'Insert column right'
              },
              'remove_row': {
                name: 'Remove row',
                disabled: function() {
                  if (hotTableRef.current) {
                    const selected = hotTableRef.current.hotInstance.getSelected();
                    if (selected && selected[0]) {
                      return selected[0][0] === 0; // Disable if first row selected
                    }
                  }
                  return false;
                }
              },
              'remove_col': {
                name: 'Remove column'
              },
              'separator1': '---------',
              'copy': {
                name: 'Copy'
              },
              'cut': {
                name: 'Cut'
              },
              'paste': {
                name: 'Paste'
              }
            }
          }}
          cells={(row: number, col: number) => {
            const cellProperties: any = {};
            
            // Make first row (headers) have different styling
            if (row === 0) {
              cellProperties.className = 'header-cell';
              cellProperties.renderer = (instance: any, td: HTMLElement, row: number, col: number, prop: any, value: any, cellProperties: any) => {
                td.style.backgroundColor = '#f3f4f6';
                td.style.fontWeight = 'bold';
                td.style.borderBottom = '2px solid #d1d5db';
                td.innerHTML = value || '';
                return td;
              };
            }
            
            return cellProperties;
          }}
          licenseKey="non-commercial-and-evaluation"
        />
      </div>
      
      
      <div className="mt-4 flex justify-end items-center space-x-2">
        <button 
          onClick={handleSaveChanges}
          className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
        >
          Save Changes
        </button>
      </div>
    </div>
  );
}
