import { http, HttpResponse } from 'msw'
import { mockDatasets, mockProjects, mockDatasetsResponse } from './data/datasets'
import { mockJobs, mockJobsResponse } from './data/jobs'

export const handlers = [
  // GET /api/v1/projects - Get user projects
  http.get('/api/v1/projects', () => {
    return HttpResponse.json({
      projects: mockProjects,
      current_user: 'alice'
    })
  }),

  // GET /api/v1/projects/:projectId/datasets - Get project datasets with filtering
  http.get('/api/v1/projects/:projectId/datasets', ({ request, params }) => {
    const url = new URL(request.url)
    const projectId = Number(params.projectId)
    
    // Extract query parameters for filtering
    const datasetName = url.searchParams.get('datasetName') || ''
    const user = url.searchParams.get('user') || ''
    const page = Number(url.searchParams.get('page')) || 1
    const per = Number(url.searchParams.get('per')) || 50

    // Filter datasets based on query parameters
    let filteredDatasets = mockDatasets.filter(dataset => 
      dataset.project_number === projectId
    )

    if (datasetName) {
      filteredDatasets = filteredDatasets.filter(dataset =>
        dataset.name.toLowerCase().includes(datasetName.toLowerCase())
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
  http.get('/api/v1/projects/:projectId/jobs', ({ request, params }) => {
    const url = new URL(request.url)
    const projectId = Number(params.projectId)
    
    // Extract query parameters for filtering
    const datasetName = url.searchParams.get('datasetName') || ''
    const user = url.searchParams.get('user') || ''
    const status = url.searchParams.get('status') || ''
    const page = Number(url.searchParams.get('page')) || 1
    const per = Number(url.searchParams.get('per')) || 50

    // Filter jobs based on query parameters
    let filteredJobs = mockJobs.filter(job => 
      job.project_id === projectId
    )

    if (datasetName) {
      filteredJobs = filteredJobs.filter(job =>
        job.dataset_name.toLowerCase().includes(datasetName.toLowerCase())
      )
    }

    if (user) {
      filteredJobs = filteredJobs.filter(job =>
        job.user_login.toLowerCase().includes(user.toLowerCase())
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

  // GET /api/v1/projects/:projectId/datasets/:datasetId - Get single dataset
  http.get('/api/v1/projects/:projectId/datasets/:datasetId', ({ params }) => {
    const datasetId = Number(params.datasetId)
    const dataset = mockDatasets.find(d => d.id === datasetId)
    
    if (!dataset) {
      return new HttpResponse(null, { status: 404 })
    }

    return HttpResponse.json(dataset)
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