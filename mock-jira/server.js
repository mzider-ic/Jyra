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

// ── Project issues for burn-up widget ─────────────────────────────────────────
// Add JYRA-1 as scope in the widget config. Stories are spread across 3 sprints
// so the burn-up chart has meaningful data to display.

const JYRA_BURN_SPRINTS = [
  { id: 500, name: 'Platform Sprint 1', state: 'closed',
    startDate: daysAgo(56), endDate: daysAgo(42) },
  { id: 501, name: 'Platform Sprint 2', state: 'closed',
    startDate: daysAgo(42), endDate: daysAgo(28) },
  { id: 502, name: 'Platform Sprint 3', state: 'active',
    startDate: daysAgo(14), endDate: daysAgo(-0) },
]

const JYRA_EPIC = {
  id: 10001, key: 'JYRA-1', summary: 'Platform Modernization',
  issueType: 'Epic', parentKey: null, storyPoints: null,
  status: 'In Progress', sprint: null,
}
const JYRA_STORIES = [
  // Sprint 1 — both Done (21 pts completed)
  { id: 10002, key: 'JYRA-2', summary: 'Migrate auth to JWT',         issueType: 'Story', parentKey: 'JYRA-1', storyPoints: 13, status: 'Done',        sprint: JYRA_BURN_SPRINTS[0] },
  { id: 10003, key: 'JYRA-3', summary: 'API versioning support',       issueType: 'Story', parentKey: 'JYRA-1', storyPoints:  8, status: 'Done',        sprint: JYRA_BURN_SPRINTS[0] },
  // Sprint 2 — JYRA-4 Done, JYRA-5 not (5 pts completed, 13 pts in progress)
  { id: 10004, key: 'JYRA-4', summary: 'Database connection pooling',  issueType: 'Story', parentKey: 'JYRA-1', storyPoints:  5, status: 'Done',        sprint: JYRA_BURN_SPRINTS[1] },
  { id: 10005, key: 'JYRA-5', summary: 'Redis caching layer',          issueType: 'Story', parentKey: 'JYRA-1', storyPoints: 13, status: 'In Progress', sprint: JYRA_BURN_SPRINTS[1] },
  // Sprint 3 (active) — none done yet
  { id: 10006, key: 'JYRA-6', summary: 'Background job queue',         issueType: 'Story', parentKey: 'JYRA-1', storyPoints:  8, status: 'To Do',       sprint: JYRA_BURN_SPRINTS[2] },
  { id: 10007, key: 'JYRA-7', summary: 'Audit logging service',        issueType: 'Story', parentKey: 'JYRA-1', storyPoints:  5, status: 'To Do',       sprint: JYRA_BURN_SPRINTS[2] },
  // Backlog — no sprint yet
  { id: 10008, key: 'JYRA-8', summary: 'Deploy pipeline v2',           issueType: 'Story', parentKey: 'JYRA-1', storyPoints: 21, status: 'To Do',       sprint: null },
  { id: 10009, key: 'JYRA-9', summary: 'Performance benchmarks',       issueType: 'Story', parentKey: 'JYRA-1', storyPoints:  3, status: 'To Do',       sprint: null },
]
const ALL_JYRA = [JYRA_EPIC, ...JYRA_STORIES]  // 76 total pts across stories

function statusCategory(s) {
  if (s === 'Done')        return { key: 'done',          name: 'Done' }
  if (s === 'In Progress') return { key: 'indeterminate', name: 'In Progress' }
  return                          { key: 'new',           name: 'To Do' }
}

// Format a JYRA issue for /rest/api/3/search or /rest/api/3/search/jql
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
      status: { name: issue.status, statusCategory: statusCategory(issue.status) },
      customfield_10020: issue.sprint ? [issue.sprint] : null,
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

  return { issues: [] }
}

// ── Calibration sprint data ───────────────────────────────────────────────────
// These issues are returned when expand=changelog is requested on the sprint
// issues endpoint. Each issue includes accountId, displayName, and a changelog
// with status transition history so CalibrationView can compute cycle times.

// Engineers that appear in calibration data
const CAL_ENGINEERS = {
  'alice-001':   { accountId: 'alice-001',   displayName: 'Alice Smith'  },
  'bob-001':     { accountId: 'bob-001',     displayName: 'Bob Johnson'  },
  'carol-001':   { accountId: 'carol-001',   displayName: 'Carol White'  },
  'charlie-001': { accountId: 'charlie-001', displayName: 'Charlie Kim'  },
  'diana-001':   { accountId: 'diana-001',   displayName: 'Diana Lee'    },
  'eve-001':     { accountId: 'eve-001',     displayName: 'Eve Martinez' },
  'frank-001':   { accountId: 'frank-001',   displayName: 'Frank Chen'   },
}

function calIssue(id, key, pts, engineerId, done, ipDaysAgo, doneDaysAgo, summary) {
  const assignee = engineerId ? CAL_ENGINEERS[engineerId] : null
  const histories = []
  if (ipDaysAgo != null) {
    histories.push({
      created: daysAgo(ipDaysAgo),
      items: [{ field: 'status', fromString: 'To Do', toString: 'In Progress' }],
    })
  }
  if (done && doneDaysAgo != null) {
    histories.push({
      created: daysAgo(doneDaysAgo),
      items: [{ field: 'status', fromString: 'In Progress', toString: 'Done' }],
    })
  }
  return {
    id: String(id), key,
    fields: {
      summary: summary || key,
      status: {
        name: done ? 'Done' : (ipDaysAgo != null ? 'In Progress' : 'To Do'),
        statusCategory: { key: done ? 'done' : (ipDaysAgo != null ? 'indeterminate' : 'new') },
      },
      story_points: pts,
      assignee: assignee || null,
    },
    changelog: { histories },
  }
}

// Board 101 (Lone Wolf) calibration issues by sprint
// Sprint 1001: closed, ran ~18–4 days ago
// Sprint 1002: active, started ~4 days ago
//
// Engineers: alice-001 (→ Senior Eng), bob-001 (→ Eng), carol-001 (→ Eng)
// Relative workloads (2 sprints, team committed 21+19=40 pts):
//   alice: 18 pts done → 45%    bob: 6 pts → 15%    carol: 3 pts → 7.5%
const CAL_SPRINT_101_1001 = [
  calIssue(31001,'LW-C1', 5,'alice-001', true,  16, 12, 'Project scaffolding'),
  calIssue(31002,'LW-C2', 8,'alice-001', true,  15, 11, 'Core authentication'),
  calIssue(31003,'LW-C3', 3,'bob-001',   true,  16, 11, 'Unit test suite setup'),
  calIssue(31004,'LW-C4', 3,'carol-001', true,  15, 12, 'CI pipeline config'),
  calIssue(31005,'LW-C5', 2,null,        false, null,null,'Unassigned backlog task'),
]

const CAL_SPRINT_101_1002 = [
  calIssue(31006,'LW-C6', 5,'alice-001', true,  4,  2,  'Auth middleware refactor'),
  calIssue(31007,'LW-C7', 3,'bob-001',   true,  3,  2,  'Fix login redirect bug'),
  calIssue(31008,'LW-C8', 8,'bob-001',   false, 3,  null,'Rate limiting design'),
  calIssue(31009,'LW-C9', 3,'carol-001', false, 4,  null,'DB schema migration'),
]

// Board 102 (Velocity Kings) calibration issues by sprint
// Engineers: charlie-001 (→ Staff), diana-001 (→ Sr Eng), eve-001 (→ Eng), frank-001 (→ Eng)
// Using last 3 closed sprints (2010, 2011, 2012) + active (2013)
// Sprint 2010: closed, ran ~46–32 days ago
// Sprint 2011: closed, ran ~32–18 days ago
// Sprint 2012: closed, ran ~18–4 days ago
// Sprint 2013: active, started ~4 days ago
//
// Relative workloads (team committed 54+52+48+37=191 pts):
//   charlie: 76 pts → 39.8%  diana: 47 pts → 24.6%
//   frank: 26 pts → 13.6%    eve: 19 pts → 9.9%
const CAL_SPRINT_102_2010 = [
  calIssue(32001,'VK-C1', 13,'charlie-001', true,  45, 39, 'Platform service mesh'),
  calIssue(32002,'VK-C2',  8,'charlie-001', true,  44, 38, 'Service discovery setup'),
  calIssue(32003,'VK-C3',  8,'diana-001',   true,  44, 39, 'Auth service v2'),
  calIssue(32004,'VK-C4',  5,'diana-001',   true,  43, 38, 'JWT refresh tokens'),
  calIssue(32005,'VK-C5',  8,'eve-001',     true,  44, 38, 'Frontend routing rebuild'),
  calIssue(32006,'VK-C6',  5,'frank-001',   true,  45, 38, 'Notification service'),
  calIssue(32007,'VK-C7',  3,'frank-001',   true,  44, 39, 'Analytics event hooks'),
  calIssue(32008,'VK-C8',  4,null,          false, null,null,'Unassigned infra spike'),
]

const CAL_SPRINT_102_2011 = [
  calIssue(32101,'VK-C9',  13,'charlie-001', true,  31, 25, 'Caching layer impl'),
  calIssue(32102,'VK-C10',  8,'charlie-001', true,  30, 24, 'DB connection pooling'),
  calIssue(32103,'VK-C11',  8,'diana-001',   true,  31, 25, 'OAuth 2.0 integration'),
  calIssue(32104,'VK-C12',  5,'diana-001',   true,  30, 25, 'Session management'),
  calIssue(32105,'VK-C13',  3,'eve-001',     true,  30, 25, 'Mobile nav redesign'),
  calIssue(32106,'VK-C14',  8,'frank-001',   true,  31, 24, 'API versioning support'),
  calIssue(32107,'VK-C15',  7,null,          false, null,null,'Unassigned task'),
]

const CAL_SPRINT_102_2012 = [
  calIssue(32201,'VK-C16', 13,'charlie-001', true,  17, 11, 'Deploy pipeline v3'),
  calIssue(32202,'VK-C17',  8,'charlie-001', true,  16, 10, 'Container orchestration'),
  calIssue(32203,'VK-C18',  8,'diana-001',   true,  17, 11, 'Rate limiting middleware'),
  calIssue(32204,'VK-C19',  5,'diana-001',   true,  16, 11, 'API gateway setup'),
  calIssue(32205,'VK-C20',  5,'eve-001',     true,  16, 11, 'Dark mode implementation'),
  calIssue(32206,'VK-C21',  8,'frank-001',   true,  17, 10, 'Email template system'),
  calIssue(32207,'VK-C22',  1,null,          false, null,null,'Unassigned cleanup'),
]

const CAL_SPRINT_102_2013 = [
  calIssue(32301,'VK-C23', 13,'charlie-001', true,  3,  1,  'Observability platform'),
  calIssue(32302,'VK-C24',  8,'diana-001',   true,  4,  2,  'SAML SSO integration'),
  calIssue(32303,'VK-C25',  3,'eve-001',     true,  3,  2,  'Accessibility fixes'),
  calIssue(32304,'VK-C26',  5,'frank-001',   true,  4,  2,  'Push notification service'),
  calIssue(32305,'VK-C27',  8,'charlie-001', false, 3,  null,'Feature flags system'),
  calIssue(32306,'VK-C28',  5,'eve-001',     false, 3,  null,'Performance profiling'),
  calIssue(32307,'VK-C29',  3,'frank-001',   false, 4,  null,'Audit log viewer'),
  calIssue(32308,'VK-C30',  8,null,          false, null,null,'Unassigned epic breakdown'),
]

// Map sprint id → calibration issues (used when expand=changelog is requested)
const CAL_SPRINT_ISSUES = {
  1001: CAL_SPRINT_101_1001,
  1002: CAL_SPRINT_101_1002,
  2010: CAL_SPRINT_102_2010,
  2011: CAL_SPRINT_102_2011,
  2012: CAL_SPRINT_102_2012,
  2013: CAL_SPRINT_102_2013,
}

// ── Board issues for the Boards feature ──────────────────────────────────────

function boardIssue(id, key, summary, status, catKey, pts, assignee, priority, type, labels, updatedDaysAgo, description) {
  return {
    id: String(id), key,
    fields: {
      summary,
      status: { name: status, statusCategory: { key: catKey } },
      story_points: pts,
      assignee: assignee ? { displayName: assignee } : null,
      priority: { name: priority },
      issuetype: { name: type },
      labels: labels || [],
      created: daysAgo(14),
      updated: daysAgo(updatedDaysAgo),
      description: description || null,
      parent: null,
    },
  }
}

const BOARD_ISSUES = {
  101: { total: 9, issues: [
    boardIssue(20001,'LW-1','Set up CI/CD pipeline',            'To Do',       'new',           5,  null,          'Medium', 'Story',  [],                   10, 'Configure GitHub Actions for automated builds and deploys.'),
    boardIssue(20002,'LW-2','Database schema migration',         'To Do',       'new',           8,  'Alice Smith',  'High',   'Story',  [],                   8,  null),
    boardIssue(20003,'LW-3','Write API documentation',           'To Do',       'new',           3,  null,          'Low',    'Task',   [],                   7,  null),
    boardIssue(20004,'LW-4','Implement authentication module',   'In Progress', 'indeterminate', 13, 'Bob Johnson',  'High',   'Story',  ['backend'],          3,  'JWT-based auth with refresh tokens.'),
    boardIssue(20005,'LW-5','Design API rate limiting',          'In Progress', 'indeterminate', 5,  'Alice Smith',  'Medium', 'Task',   ['blocked'],          5,  'Blocked waiting on security review.'),
    boardIssue(20006,'LW-6','Write unit tests for data layer',   'In Progress', 'indeterminate', 3,  'Carol White',  'Low',    'Task',   [],                   1,  null),
    boardIssue(20007,'LW-7','Refactor legacy auth middleware',   'In Progress', 'indeterminate', 8,  'Bob Johnson',  'High',   'Story',  ['backend','urgent'],  6,  'This has been sitting here for a while.'),
    boardIssue(20008,'LW-8','Project scaffolding and setup',     'Done',        'done',          5,  'Bob Johnson',  'High',   'Story',  [],                   10, null),
    boardIssue(20009,'LW-9','Repository structure and branching','Done',        'done',          2,  'Alice Smith',  'Medium', 'Task',   [],                   11, null),
  ]},
  102: { total: 11, issues: [
    boardIssue(20101,'VK-1','User onboarding flow redesign',     'To Do',       'new',           13, null,          'High',   'Story',  [],                   5,  'Complete redesign of the first-run experience.'),
    boardIssue(20102,'VK-2','Mobile push notification support',  'To Do',       'new',           8,  'Dana Lee',    'Medium', 'Story',  [],                   3,  null),
    boardIssue(20103,'VK-3','Analytics pipeline v2',             'To Do',       'new',           21, null,          'Critical','Epic',  [],                   2,  'Full pipeline rewrite for scale.'),
    boardIssue(20104,'VK-4','Payment gateway integration',       'In Progress', 'indeterminate', 13, 'Eve Martinez', 'Critical','Story', ['backend','blocked'], 8,  'Blocked on merchant account approval.'),
    boardIssue(20105,'VK-5','Reporting dashboard',               'In Progress', 'indeterminate', 8,  'Frank Chen',  'High',   'Story',  ['frontend'],         2,  null),
    boardIssue(20106,'VK-6','Email notification templates',      'In Progress', 'indeterminate', 5,  'Dana Lee',    'Medium', 'Task',   [],                   1,  null),
    boardIssue(20107,'VK-7','Performance profiling',             'In Progress', 'indeterminate', 5,  'Eve Martinez', 'High',  'Task',   ['urgent'],           7,  null),
    boardIssue(20108,'VK-8','SSO implementation',                'In Progress', 'indeterminate', 13, 'Frank Chen',  'High',   'Story',  ['backend'],          4,  'SAML 2.0 and OIDC support.'),
    boardIssue(20109,'VK-9','User profile page',                 'Done',        'done',          5,  'Dana Lee',    'Medium', 'Story',  [],                   12, null),
    boardIssue(20110,'VK-10','Notification preferences',         'Done',        'done',          3,  'Frank Chen',  'Low',    'Task',   [],                   13, null),
    boardIssue(20111,'VK-11','Dark mode support',                'Done',        'done',          8,  'Eve Martinez', 'Low',   'Story',  ['frontend'],         15, null),
  ]},
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
  { id: 'story_points',       name: 'Story Points', custom: true,  schema: { type: 'number' } },
  { id: 'summary',            name: 'Summary',      custom: false, schema: { type: 'string' } },
  { id: 'status',             name: 'Status',       custom: false, schema: { type: 'status' } },
  { id: 'customfield_10020',  name: 'Sprint',       custom: true,  schema: { type: 'array', items: 'json' } },
]

// ── HTTP server ───────────────────────────────────────────────────────────────

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true)
  const path   = parsed.pathname
  const q      = parsed.query
  const t0     = Date.now()

  res.setHeader('Content-Type', 'application/json')
  res.setHeader('Access-Control-Allow-Origin', '*')

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return }

  function send(body, status = 200) {
    const bodyStr = JSON.stringify(body)
    const ms      = Date.now() - t0
    const bytes   = Buffer.byteLength(bodyStr)
    const size    = bytes >= 1024 ? `${(bytes / 1024).toFixed(1)}KB` : `${bytes}B`
    const color   = status < 300 ? '\x1b[32m' : status < 500 ? '\x1b[33m' : '\x1b[31m'
    console.log(`  ${color}${req.method} ${status}\x1b[0m  ${String(ms + 'ms').padEnd(6)}  ${size.padStart(7)}  ${req.url}`)
    res.writeHead(status)
    res.end(bodyStr)
  }

  function notFound() {
    const ms = Date.now() - t0
    console.warn(`  \x1b[31m${req.method} 404\x1b[0m  ${ms}ms            ${req.url}`)
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
  const sprintIssues = path.match(/^\/rest\/agile\/1\.0\/board\/(\d+)\/sprint\/(\d+)\/issue$/)
  if (sprintIssues) {
    const boardId  = parseInt(sprintIssues[1])
    const sprintId = parseInt(sprintIssues[2])
    // Calibration requests include expand=changelog; serve rich data with engineers + changelog
    if (q.expand && q.expand.includes('changelog') && CAL_SPRINT_ISSUES[sprintId]) {
      const issues = CAL_SPRINT_ISSUES[sprintId]
      return send({ issues, total: issues.length })
    }
    // Burndown / velocity: use existing board-level issue data
    return send(ISSUES_BY_BOARD[boardId] || { issues: [], total: 0 })
  }

  // /rest/agile/1.0/board/:id/issue  — board view (all active issues)
  const boardIssues = path.match(/^\/rest\/agile\/1\.0\/board\/(\d+)\/issue$/)
  if (boardIssues) {
    const boardId  = parseInt(boardIssues[1])
    const data     = BOARD_ISSUES[boardId]
    const startAt  = parseInt(q.startAt || '0')
    const maxRes   = parseInt(q.maxResults || '100')
    if (!data) return send({ issues: [], total: 0, startAt: 0, maxResults: maxRes })
    const page = data.issues.slice(startAt, startAt + maxRes)
    return send({ issues: page, total: data.total, startAt, maxResults: maxRes })
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

  // /rest/api/3/search — legacy GET endpoint (kept for other callers)
  if (path === '/rest/api/3/search' && req.method !== 'POST') {
    const jql = q.jql || ''
    const result = jqlFilter(jql)
    if (result.statusCode) {
      return send(result.body, result.statusCode)
    }
    return send({ issues: result.issues, total: result.issues.length, startAt: 0, maxResults: 100 })
  }

  // /rest/api/3/search/jql — GET with query params (Jira Cloud v3)
  if (path === '/rest/api/3/search/jql' && req.method === 'GET') {
    const jql = q.jql || ''
    const result = jqlFilter(jql)
    if (result.statusCode) {
      return send(result.body, result.statusCode)
    }
    return send({ issues: result.issues, total: result.issues.length, startAt: 0, maxResults: 100 })
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

  Calibration: boards 101 and 102 have rich engineer + changelog data (expand=changelog)
    Board 101 engineers: alice-001 (Sr. Eng target), bob-001 (Eng), carol-001 (Eng)
    Board 102 engineers: charlie-001 (Staff), diana-001 (Sr. Eng), eve-001 (Eng), frank-001 (Eng)

  Logs: /tmp/jyra-mock.log
  Stop: bash mock-jira/stop.sh
`)
})

process.on('SIGTERM', () => { server.close(); process.exit(0) })
process.on('SIGINT',  () => { server.close(); process.exit(0) })
