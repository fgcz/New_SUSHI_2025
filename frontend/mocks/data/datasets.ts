export const mockDatasets = [
  {
    id: 1,
    name: "RNA-seq Analysis Dataset",
    app_name: "RNASeqAnalysis",
    completed_samples: 45,
    samples_count: 50,
    parent_id: null,
    children_ids: [2, 3],
    user_login: "alice",
    created_at: "2024-01-15T10:30:00Z",
    bfabric_id: 12345,
    project_number: 1001,
  },
  {
    id: 2,
    name: "Quality Control Report",
    app_name: "FastQC",
    completed_samples: 50,
    samples_count: 50,
    parent_id: 1,
    children_ids: [],
    user_login: "alice",
    created_at: "2024-01-16T14:20:00Z",
    bfabric_id: 12346,
    project_number: 1001,
  },
  {
    id: 3,
    name: "Differential Expression",
    app_name: "EdgeR",
    completed_samples: 30,
    samples_count: 45,
    parent_id: 1,
    children_ids: [4],
    user_login: "bob",
    created_at: "2024-01-17T09:15:00Z",
    bfabric_id: 12347,
    project_number: 1001,
  },
  {
    id: 4,
    name: "Pathway Analysis",
    app_name: "GSEA",
    completed_samples: 0,
    samples_count: 20,
    parent_id: 3,
    children_ids: [],
    user_login: "charlie",
    created_at: "2024-01-18T16:45:00Z",
    bfabric_id: null,
    project_number: 1001,
  },
  {
    id: 5,
    name: "Proteomics Dataset",
    app_name: "MaxQuant",
    completed_samples: 25,
    samples_count: 30,
    parent_id: null,
    children_ids: [],
    user_login: "diana",
    created_at: "2024-01-19T11:30:00Z",
    bfabric_id: 12348,
    project_number: 1001,
  },
];

export const mockProjects = [
  {
    id: 1001,
    name: "Cancer Research Project",
    description: "Multi-omics analysis of cancer samples",
    current_user: "alice",
  },
  {
    id: 1002,
    name: "Plant Genomics Study",
    description: "Comparative genomics of plant species",
    current_user: "bob",
  },
];

export const mockDatasetsResponse = {
  datasets: mockDatasets,
  total_count: mockDatasets.length,
  page: 1,
  per: 50,
  project_number: 1001,
};

// Full dataset response for detail page
export const mockDatasetFull = {
  id: 1,
  name: "RNA-seq Analysis Dataset",
  created_at: "2024-01-15T10:30:00Z",
  user_login: "alice",
  project_number: 1001,
  samples_count: 50,
  completed_samples: 45,
  parent_id: null,
  children_ids: [2, 3],
  bfabric_id: 12345,
  order_id: 9001,
  comment: "Initial RNA-seq analysis",
  app_name: "RNASeqAnalysis",
  samples: [
    { id: 101, name: "Sample_A1", status: "completed", read_count: 25000000 },
    { id: 102, name: "Sample_A2", status: "completed", read_count: 28000000 },
    { id: 103, name: "Sample_B1", status: "completed", read_count: 22000000 },
  ],
  applications: [
    {
      category: "QC",
      apps: [
        { class_name: "FastQC", description: "Quality control for sequencing data" },
        { class_name: "MultiQC", description: "Aggregate QC reports" },
      ],
    },
    {
      category: "Alignment",
      apps: [
        { class_name: "STAR", description: "RNA-seq aligner" },
        { class_name: "HISAT2", description: "Graph-based alignment" },
      ],
    },
  ],
};

// Dataset tree for detail page
export const mockDatasetTree = [
  { id: 1, name: "RNA-seq Analysis Dataset", comment: "Root dataset", parent: "#" as const },
  { id: 2, name: "Quality Control Report", comment: "QC results", parent: 1 },
  { id: 3, name: "Differential Expression", comment: "DE analysis", parent: 1 },
  { id: 4, name: "Pathway Analysis", comment: null, parent: 3 },
];