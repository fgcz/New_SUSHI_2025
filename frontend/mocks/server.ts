import { setupServer } from 'msw/node'
import { handlers } from './handlers'

// Setup MSW server for Node.js test environment
export const server = setupServer(...handlers)

// Enable API mocking before all tests
beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' })
})

// Reset handlers after each test to ensure test isolation
afterEach(() => {
  server.resetHandlers()
})

// Clean up after all tests
afterAll(() => {
  server.close()
})