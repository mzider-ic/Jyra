#!/usr/bin/env node
// Mock Jira server for local Jyra development — no npm required (built-in http only)
// Start: node mock-jira/server.js   OR use the "Jyra (Mock)" Xcode scheme

const http = require('http')
const url  = require('url')

const PORT = process.env.MOCK_PORT || 3001

// ── Helpers ───────────────────────────────────────────────────────────────────

function daysAgo(n) {
  const d = new Date()
  d.setDate(d.getDate() - n)   // negative n = future date
  return d.toISOString()
}

function sprint(id, name, state, startDaysAgo, endDaysAgo, completeDaysAgo = null) {
  return {
    id,
    name,
    state,
    startDate:    startDaysAgo    != null ? daysAgo(startDaysAgo)    : null,
    endDate:      endDaysAgo      != null ? daysAgo(endDaysAgo)      : null,
    completeDate: completeDaysAgo != null ? daysAgo(completeDaysAgo) : null,
  }
}

function stat(committed, completed) {
  return { estimated: { value: committed }, completed: { value: completed } }
}

// Issues for an active sprint. Each task: { pts, done, resolvedDaysAgo? }
function makeIssues(prefix, sprintId, tasks) {
  return {
    issues: tasks.map((t, i) => ({
      id:  `${sprintId}${i}`,
      key: `${prefix}-${100 + i}`,
      fields: {
        summary: `Task ${i + 1}`,
        status: {
          name: t.done ? 'Done' : 'In Progress',
          statusCategory: { key: t.done ? 'done' : 'indeterminate' },
        },
        created:         daysAgo(12),
        resolutiondate:  t.done ? daysAgo(t.resolvedDaysAgo !== undefined ? t.resolvedDaysAgo : 2) : null,
        story_points:    t.pts,
      },
    })),
    total: tasks.length,
  }
}

// Build a velocity response object from parallel arrays of [committed, completed]
function velocityFixture(prefix, closedIds, statsMatrix) {
  return {
    sprints: closedIds.map((id, i) => ({
      id, name: `${prefix} Sprint ${i + 1}`, state: 'closed',
    })),
    velocityStatEntries: Object.fromEntries(
      closedIds.map((id, i) => [String(id), stat(statsMatrix[i][0], statsMatrix[i][1])])
    ),
    transactionId: null,
  }
}

// Build closed-sprint objects going back in 2-week increments
function closedSprints(prefix, ids, activeStartDaysAgo = 4) {
  return ids.map((id, i) => {
    const offset = (ids.length - i) * 14
    return sprint(id, `${prefix} Sprint ${i + 1}`, 'closed',
      offset + activeStartDaysAgo,
      offset - (14 - activeStartDaysAgo),
      offset - (14 - activeStartDaysAgo))
  })
}

// ── Board 101: Lone Wolf — 1 completed sprint, then active ───────────────────
const LW_IDS   = [1001]
const LW_STATS = [[15, 12]]

const LW_SPRINTS = [
  ...closedSprints('LW', LW_IDS),
  sprint(1002, 'LW Sprint 2', 'active', 4, -10, null),
]
const LW_VELOCITY      = velocityFixture('LW', LW_IDS, LW_STATS)
const LW_ACTIVE_ISSUES = makeIssues('LW', 1002, [
  { pts: 5, done: true,  resolvedDaysAgo: 3 },
  { pts: 8, done: false },
  { pts: 3, done: true,  resolvedDaysAgo: 1 },
  { pts: 5, done: false },
])

// ── Board 102: Velocity Kings — 12 closed sprints, varied commitment/completion
const VK_IDS = Array.from({ length: 12 }, (_, i) => 2001 + i)
const VK_STATS = [
  [30, 25],   // S1  83%
  [35, 40],   // S2  114% over-delivered
  [40, 32],   // S3  80%
  [45, 45],   // S4  100% perfect
  [50, 20],   // S5  40%  rough sprint
  [42, 38],   // S6  90%
  [38, 38],   // S7  100% perfect
  [55, 50],   // S8  91%  high commitment
  [48, 42],   // S9  88%
  [52, 55],   // S10 106% over-delivered
  [44, 40],   // S11 91%
  [50, 47],   // S12 94%
]

const VK_SPRINTS = [
  ...closedSprints('VK', VK_IDS),
  sprint(2013, 'VK Sprint 13', 'active', 4, -10, null),
]
const VK_VELOCITY      = velocityFixture('VK', VK_IDS, VK_STATS)
const VK_ACTIVE_ISSUES = makeIssues('VK', 2013, [
  { pts:  8, done: true,  resolvedDaysAgo: 3 },
  { pts:  5, done: true,  resolvedDaysAgo: 3 },
  { pts: 13, done: false },
  { pts:  8, done: false },
  { pts:  3, done: true,  resolvedDaysAgo: 1 },
  { pts:  5, done: false },
  { pts:  8, done: false },
])

// ── Board 103: Zero Gap — sprint 4 has 0 points (filtered from velocity display)
const ZG_IDS = Array.from({ length: 7 }, (_, i) => 3001 + i)
const ZG_STATS = [
  [30, 25],  // S1
  [35, 30],  // S2
  [32, 28],  // S3
  [ 0,  0],  // S4 ← zero points — widget must exclude this
  [40, 38],  // S5
  [38, 35],  // S6
  [42, 40],  // S7
]

const ZG_SPRINTS = [
  ...closedSprints('ZG', ZG_IDS),
  sprint(3008, 'ZG Sprint 8', 'active', 4, -10, null),
]
const ZG_VELOCITY      = velocityFixture('ZG', ZG_IDS, ZG_STATS)
const ZG_ACTIVE_ISSUES = makeIssues('ZG', 3008, [
  { pts: 5, done: false },
  { pts: 8, done: true,  resolvedDaysAgo: 2 },
  { pts: 5, done: false },
  { pts: 3, done: true,  resolvedDaysAgo: 1 },
])

// ── Board 104: Steady Rhythms — 5 consistent sprints ─────────────────────────
const SR_IDS = Array.from({ length: 5 }, (_, i) => 4001 + i)
const SR_STATS = [
  [40, 38],  // S1 95%
  [42, 40],  // S2 95%
  [38, 36],  // S3 95%
  [44, 42],  // S4 95%
  [40, 37],  // S5 93%
]

const SR_SPRINTS = [
  ...closedSprints('SR', SR_IDS),
  sprint(4006, 'SR Sprint 6', 'active', 4, -10, null),
]
const SR_VELOCITY      = velocityFixture('SR', SR_IDS, SR_STATS)
const SR_ACTIVE_ISSUES = makeIssues('SR', 4006, [
  { pts: 8, done: true,  resolvedDaysAgo: 3 },
  { pts: 8, done: true,  resolvedDaysAgo: 2 },
  { pts: 5, done: false },
  { pts: 5, done: false },
  { pts: 8, done: false },
  { pts: 3, done: true,  resolvedDaysAgo: 1 },
])

// ── Board 201: No-Dates Team — sprints without start/end dates ────────────────
// Velocity still works; burndown widget will show "missing sprint dates" error.
const ND_IDS   = [5001, 5002, 5003]
const ND_STATS = [[20, 18], [25, 22], [22, 20]]

const ND_SPRINTS = [
  { id: 5001, name: 'ND Sprint 1', state: 'closed', startDate: null, endDate: null, completeDate: daysAgo(42) },
  { id: 5002, name: 'ND Sprint 2', state: 'closed', startDate: null, endDate: null, completeDate: daysAgo(28) },
  { id: 5003, name: 'ND Sprint 3', state: 'closed', startDate: null, endDate: null, completeDate: daysAgo(14) },
  { id: 5004, name: 'ND Sprint 4', state: 'active', startDate: null, endDate: null, completeDate: null },
]
const ND_VELOCITY      = velocityFixture('ND', ND_IDS, ND_STATS)
const ND_ACTIVE_ISSUES = makeIssues('ND', 5004, [
  { pts: 5, done: true,  resolvedDaysAgo: 2 },
  { pts: 8, done: false },
  { pts: 3, done: false },
])

// ── Project issues for /rest/api/3/search and /issue/picker ──────────────────
// Use these to test the Project Burn Rate widget.
// Add JYRA-1 as scope, child stories (JYRA-2…JYRA-9) supply the point total.
const JYRA_EPIC = {
  id: 10001, key: 'JYRA-1', summary: 'Platform Modernization',
  issueType: 'Epic', parentKey: null, storyPoints: null,
}
const JYRA_STORIES = [
  { id: 10002, key: 'JYRA-2', summary: 'Migrate auth to JWT',          issueType: 'Story', parentKey: 'JYRA-1', storyPoints: 13 },
  { id: 10003, key: 'JYRA-3', summary: 'API versioning support',        issueType: 'Story', parentKey: 'JYRA-1', storyPoints:  8 },
  { id: 10004, key: 'JYRA-4', summary: 'Database connection pooling',   issueType: 'Story', parentKey: 'JYRA-1', storyPoints:  5 },
  { id: 10005, key: 'JYRA-5', summary: 'Redis caching layer',           issueType: 'Story', parentKey: 'JYRA-1', storyPoints: 13 },
  { id: 10006, key: 'JYRA-6', summary: 'Background job queue',          issueType: 'Story', parentKey: 'JYRA-1', storyPoints:  8 },
  { id: 10007, key: 'JYRA-7', summary: 'Audit logging service',         issueType: 'Story', parentKey: 'JYRA-1', storyPoints:  5 },
  { id: 10008, key: 'JYRA-8', summary: 'Deploy pipeline v2',            issueType: 'Story', parentKey: 'JYRA-1', storyPoints: 21 },
  { id: 10009, key: 'JYRA-9', summary: 'Performance benchmarks',        issueType: 'Story', parentKey: 'JYRA-1', storyPoints:  3 },
]
const ALL_JYRA = [JYRA_EPIC, ...JYRA_STORIES]  // 76 total story points across children

// Format a JYRA issue into the shape /rest/api/3/search returns
// Real Jira: search returns id as string, picker returns id as int
function jiraSearchIssue(issue) {
  return {
    id: String(issue.id),
    key: issue.key,
    fields: {
      summary: issue.summary,
      issuetype: { name: issue.issueType },
      parent: issue.parentKey ? { key: issue.parentKey } : undefined,
      story_points: issue.storyPoints,
    },
  }
}

// Parse a simple JQL expression to filter ALL_JYRA
function jqlFilter(jql) {
  const j = jql.toLowerCase()

  // issuekey in ("JYRA-1", "JYRA-2", ...)
  const keyMatch = j.match(/issuekey\s+in\s*\(([^)]+)\)/)
  if (keyMatch) {
    const keys = keyMatch[1].split(',').map(s => s.trim().replace(/['"]/g, '').toUpperCase())
    return { issues: ALL_JYRA.filter(i => keys.includes(i.key)).map(jiraSearchIssue) }
  }

  // parent in (...)
  const parentMatch = j.match(/parent\s+in\s*\(([^)]+)\)/)
  if (parentMatch) {
    const parents = parentMatch[1].split(',').map(s => s.trim().replace(/['"]/g, '').toUpperCase())
    return { issues: ALL_JYRA.filter(i => i.parentKey && parents.includes(i.parentKey)).map(jiraSearchIssue) }
  }

  // "Epic Link" in (...) — Jira Cloud returns 400 for this
  if (j.includes('epic link')) {
    return { statusCode: 400, body: { errorMessages: ['"Epic Link" is not supported in Jira Cloud'] } }
  }

  return { issues: [] }
}

// ── Index tables ──────────────────────────────────────────────────────────────

const BOARDS = [
  { id: 101, name: 'Lone Wolf',      type: 'scrum' },
  { id: 102, name: 'Velocity Kings', type: 'scrum' },
  { id: 103, name: 'Zero Gap',       type: 'scrum' },
  { id: 104, name: 'Steady Rhythms', type: 'scrum' },
  { id: 201, name: 'No-Dates Team',  type: 'scrum' },
]

const SPRINTS_BY_BOARD  = { 101: LW_SPRINTS, 102: VK_SPRINTS, 103: ZG_SPRINTS, 104: SR_SPRINTS, 201: ND_SPRINTS }
const VELOCITY_BY_BOARD = { 101: LW_VELOCITY, 102: VK_VELOCITY, 103: ZG_VELOCITY, 104: SR_VELOCITY, 201: ND_VELOCITY }
const ISSUES_BY_BOARD   = { 101: LW_ACTIVE_ISSUES, 102: VK_ACTIVE_ISSUES, 103: ZG_ACTIVE_ISSUES, 104: SR_ACTIVE_ISSUES, 201: ND_ACTIVE_ISSUES }

const FIELDS = [
  { id: 'story_points', name: 'Story Points', custom: true,  schema: { type: 'number' } },
  { id: 'summary',      name: 'Summary',      custom: false, schema: { type: 'string' } },
  { id: 'status',       name: 'Status',       custom: false, schema: { type: 'status' } },
]

// ── HTTP server ───────────────────────────────────────────────────────────────

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true)
  const path   = parsed.pathname
  const q      = parsed.query

  res.setHeader('Content-Type', 'application/json')
  res.setHeader('Access-Control-Allow-Origin', '*')

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return }

  console.log(`  ${req.method} ${req.url}`)

  function send(body, status = 200) { res.writeHead(status); res.end(JSON.stringify(body)) }
  function notFound() {
    console.warn(`  404 — no handler for: ${path}`)
    res.writeHead(404)
    res.end(JSON.stringify({ message: `Mock: unhandled path ${path}` }))
  }

  // /rest/api/3/myself
  if (path === '/rest/api/3/myself') {
    return send({ displayName: 'Mock User', emailAddress: 'mock@example.com', accountId: 'mock-001' })
  }

  // /rest/api/3/field
  if (path === '/rest/api/3/field') {
    return send(FIELDS)
  }

  // /rest/agile/1.0/board
  if (path === '/rest/agile/1.0/board') {
    const name     = (q.name || '').toLowerCase()
    const filtered = name ? BOARDS.filter(b => b.name.toLowerCase().includes(name)) : BOARDS
    return send({ values: filtered, isLast: true, startAt: 0, maxResults: 50, total: filtered.length })
  }

  // /rest/agile/1.0/board/:id/sprint
  const sprintList = path.match(/^\/rest\/agile\/1\.0\/board\/(\d+)\/sprint$/)
  if (sprintList) {
    const boardId = parseInt(sprintList[1])
    const all     = SPRINTS_BY_BOARD[boardId] || []
    const state   = q.state
    const values  = state ? all.filter(s => s.state === state) : all
    return send({ values, isLast: true })
  }

  // /rest/agile/1.0/board/:id/sprint/:sprintId/issue
  const sprintIssues = path.match(/^\/rest\/agile\/1\.0\/board\/(\d+)\/sprint\/\d+\/issue$/)
  if (sprintIssues) {
    const boardId = parseInt(sprintIssues[1])
    return send(ISSUES_BY_BOARD[boardId] || { issues: [], total: 0 })
  }

  // /rest/greenhopper/1.0/rapid/charts/velocity
  if (path === '/rest/greenhopper/1.0/rapid/charts/velocity') {
    const boardId = parseInt(q.rapidViewId)
    return send(VELOCITY_BY_BOARD[boardId] || { sprints: [], velocityStatEntries: {}, transactionId: null })
  }

  // /rest/api/3/issue/picker — used by AddWidget board search and scope selection
  if (path === '/rest/api/3/issue/picker') {
    const query = (q.query || '').toLowerCase()
    const matches = ALL_JYRA.filter(i =>
      i.key.toLowerCase().includes(query) ||
      i.summary.toLowerCase().includes(query) ||
      (i.issueType && i.issueType.toLowerCase().includes(query))
    )
    return send({
      sections: [{
        id: 'cs',
        label: 'Current Search',
        issues: matches.slice(0, 10).map(i => ({
          id: i.id,
          key: i.key,
          summary: i.summary,
          img: '',
          subtitle: i.issueType,
        })),
      }],
    })
  }

  // /rest/api/3/search — used by Project Burn Rate scope resolution
  if (path === '/rest/api/3/search') {
    const jql = q.jql || ''
    const result = jqlFilter(jql)
    if (result.statusCode) {
      return send(result.body, result.statusCode)
    }
    const issues = result.issues
    return send({ issues, total: issues.length, startAt: 0, maxResults: 100 })
  }

  notFound()
})

server.listen(PORT, '127.0.0.1', () => {
  console.log(`\n  Mock Jira server  http://localhost:${PORT}\n`)
  console.log('  Boards:')
  BOARDS.forEach(b => console.log(`    ${b.id}  ${b.name}`))
  console.log(`
  Lone Wolf      (101)  1 completed sprint, realistic burndown spread
  Velocity Kings (102)  12 sprints, wildly varied commitment & completion
  Zero Gap       (103)  sprint 4 has 0 points — filtered by velocity widget
  Steady Rhythms (104)  5 consistent ~95% sprints
  No-Dates Team  (201)  sprints with null start/end — velocity works, burndown errors

  Project Burn Rate scope: search "JYRA" in issue picker (JYRA-1 epic, 76 pts across 8 stories)

  Logs: /tmp/jyra-mock.log
  Stop: bash mock-jira/stop.sh
`)
})

process.on('SIGTERM', () => { server.close(); process.exit(0) })
process.on('SIGINT',  () => { server.close(); process.exit(0) })
