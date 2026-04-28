import { http, HttpResponse } from 'msw'
import { mockDatasets, mockProjects, mockDatasetsResponse, mockDatasetFull, mockDatasetTree } from './data/datasets'
import { mockJobs, mockJobsResponse } from './data/jobs'

export const handlers = [
  // GET /api/v1/projects - Get user projects
  http.get('*/api/v1/projects', () => {
    return HttpResponse.json({
      projects: mockProjects,
      current_user: 'alice'
    })
  }),

  // GET /api/v1/projects/:projectId/datasets - Get project datasets with filtering
  http.get('*/api/v1/projects/:projectId/datasets', ({ request, params }) => {
    const url = new URL(request.url)
    const projectId = Number(params.projectId)
    
    // Extract query parameters for filtering
    const q = url.searchParams.get('q') || ''
    const user = url.searchParams.get('user') || ''
    const page = Number(url.searchParams.get('page')) || 1
    const per = Number(url.searchParams.get('per')) || 50

    // Filter datasets based on query parameters
    let filteredDatasets = mockDatasets.filter(dataset =>
      dataset.project_number === projectId
    )

    if (q) {
      filteredDatasets = filteredDatasets.filter(dataset =>
        dataset.name.toLowerCase().includes(q.toLowerCase())
      )
    }

    if (user) {
      filteredDatasets = filteredDatasets.filter(dataset =>
        dataset.user_login.toLowerCase().includes(user.toLowerCase())
      )
    }

    // Apply pagination
    const startIndex = (page - 1) * per
    const endIndex = startIndex + per
    const paginatedDatasets = filteredDatasets.slice(startIndex, endIndex)

    return HttpResponse.json({
      datasets: paginatedDatasets,
      total_count: filteredDatasets.length,
      page,
      per,
      project_number: projectId,
    })
  }),

  // GET /api/v1/projects/:projectId/jobs - Get project jobs with filtering
  http.get('*/api/v1/projects/:projectId/jobs', ({ request, params }) => {
    const url = new URL(request.url)
    const projectId = Number(params.projectId)

    // Extract query parameters for filtering
    const user = url.searchParams.get('user') || ''
    const status = url.searchParams.get('status') || ''
    const page = Number(url.searchParams.get('page')) || 1
    const per = Number(url.searchParams.get('per')) || 50

    // Filter jobs based on query parameters
    let filteredJobs = mockJobs.filter(job =>
      job.project_id === projectId
    )

    if (user) {
      filteredJobs = filteredJobs.filter(job =>
        job.user.toLowerCase().includes(user.toLowerCase())
      )
    }

    if (status) {
      filteredJobs = filteredJobs.filter(job =>
        job.status.toLowerCase().includes(status.toLowerCase())
      )
    }

    // Apply pagination
    const startIndex = (page - 1) * per
    const endIndex = startIndex + per
    const paginatedJobs = filteredJobs.slice(startIndex, endIndex)

    return HttpResponse.json({
      jobs: paginatedJobs,
      total_count: filteredJobs.length,
      page,
      per,
      project_id: projectId,
    })
  }),

  // GET /api/v1/projects/:projectId/datasets/tree - Get project datasets tree
  http.get('*/api/v1/projects/:projectId/datasets/tree', () => {
    return HttpResponse.json({
      tree: mockDatasetTree,
    })
  }),

  // GET /api/v1/projects/:projectId/datasets/:datasetId - Get single dataset (legacy)
  http.get('*/api/v1/projects/:projectId/datasets/:datasetId', ({ params }) => {
    const datasetId = Number(params.datasetId)
    const dataset = mockDatasets.find(d => d.id === datasetId)

    if (!dataset) {
      return new HttpResponse(null, { status: 404 })
    }

    return HttpResponse.json(dataset)
  }),

  // GET /api/v1/datasets/:datasetId - Get full dataset details
  http.get('*/api/v1/datasets/:datasetId', ({ params }) => {
    const datasetId = Number(params.datasetId)

    if (datasetId === 1) {
      return HttpResponse.json(mockDatasetFull)
    }

    // For other IDs, return a minimal version based on mockDatasets
    const dataset = mockDatasets.find(d => d.id === datasetId)
    if (!dataset) {
      return new HttpResponse(null, { status: 404 })
    }

    return HttpResponse.json({
      ...dataset,
      samples: [],
      applications: [],
    })
  }),

  // GET /api/v1/datasets/:datasetId/tree - Get dataset tree
  http.get('*/api/v1/datasets/:datasetId/tree', ({ params }) => {
    const datasetId = Number(params.datasetId)

    // Return tree filtered to show relevant nodes
    const tree = mockDatasetTree.filter(node =>
      node.id === datasetId ||
      node.parent === datasetId ||
      node.parent === "#"
    )

    return HttpResponse.json(tree.length > 0 ? tree : mockDatasetTree)
  }),

  // GET /api/v1/applications/:appName - Get application form schema
  http.get('*/api/v1/applications/:appName', ({ params }) => {
    const appName = params.appName

    return HttpResponse.json({
      application: {
        name: appName,
        category: 'Analysis',
        description: `Mock application: ${appName}`,
        required_columns: ['Name'],
        required_params: ['cores'],
        param_groups: [
          {
            id: 'resources',
            title: 'Resource Parameters',
            description: 'Configure compute resources',
            fields: [
              { name: 'cores', type: 'integer', default_value: 4, description: 'CPU cores' },
              { name: 'ram', type: 'integer', default_value: 16, description: 'RAM in GB' },
            ],
          },
        ],
      },
    })
  }),

  // Error simulation handlers (useful for testing error states)
  // Uncomment these to test error handling
  /*
  http.get('/api/v1/projects/9999/datasets', () => {
    return new HttpResponse(null, { status: 500 })
  }),

  http.get('/api/v1/projects/timeout/datasets', async () => {
    // Simulate slow response
    await new Promise(resolve => setTimeout(resolve, 5000))
    return HttpResponse.json(mockDatasetsResponse)
  }),
  */
]