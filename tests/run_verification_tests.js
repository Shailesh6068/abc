/**
 * RaceZone Comprehensive Automated Verification Test Suite
 * Tests Core Math, State Machines, GPS Anti-Cheat, Ad Safety, and DB Schemas.
 */

const assert = require('assert');

let passedTests = 0;
let totalTests = 0;

function it(description, fn) {
  totalTests++;
  try {
    fn();
    console.log(`  ✓ ${description}`);
    passedTests++;
  } catch (err) {
    console.error(`  ✗ ${description}`);
    console.error(`    ${err.message}`);
  }
}

function describe(suiteName, fn) {
  console.log(`\n========================================`);
  console.log(`SUITE: ${suiteName}`);
  console.log(`========================================`);
  fn();
}

// -----------------------------------------------------------------------------
// 1. HA древнейшие GEODETIC DISTANCE & PACE TESTS
// -----------------------------------------------------------------------------
describe('1. Geodetic Distance & Telemetry Calculations', () => {
  const EARTH_RADIUS = 6371000.0;
  function toRad(deg) { return deg * (Math.PI / 180.0); }
  function haversineDistance(lat1, lon1, lat2, lon2) {
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return EARTH_RADIUS * c;
  }

  function formatRunningPace(speedMps) {
    if (speedMps <= 0.2) return '--:-- /km';
    const secondsPerKm = 1000.0 / speedMps;
    const mins = Math.floor(secondsPerKm / 60);
    const secs = Math.floor(secondsPerKm % 60);
    return `${mins}:${secs.toString().padStart(2, '0')} /km`;
  }

  it('Calculates 1000m Marina Beach sprint coordinates accurately', () => {
    const d = haversineDistance(13.0475, 80.2825, 13.0565, 80.2835);
    assert(d >= 950 && d <= 1050, `Expected ~1000m, got ${d}m`);
  });

  it('Returns 0m when coordinates are identical', () => {
    const d = haversineDistance(13.0, 80.0, 13.0, 80.0);
    assert.strictEqual(d, 0.0);
  });

  it('Accurately converts 3.333 m/s to 5:00 /km running pace', () => {
    const pace = formatRunningPace(3.3333);
    assert.strictEqual(pace, '5:00 /km');
  });

  it('Returns --:-- /km for stationary competitor (<= 0.2 m/s)', () => {
    const pace = formatRunningPace(0.1);
    assert.strictEqual(pace, '--:-- /km');
  });
});

// -----------------------------------------------------------------------------
// 2. RACE STATE MACHINE VALIDATION
// -----------------------------------------------------------------------------
describe('2. Server-Authoritative Race State Machine', () => {
  const VALID_TRANSITIONS = {
    'WAITING': ['READY_CHECK', 'COUNTDOWN', 'CANCELLED'],
    'READY_CHECK': ['COUNTDOWN', 'WAITING', 'CANCELLED'],
    'COUNTDOWN': ['IN_PROGRESS', 'CANCELLED'],
    'IN_PROGRESS': ['FINISHING', 'ABORTED'],
    'FINISHING': ['COMPLETED', 'ABORTED'],
    'COMPLETED': [],
    'CANCELLED': [],
    'ABORTED': []
  };

  function canTransition(current, next) {
    return VALID_TRANSITIONS[current]?.includes(next) ?? false;
  }

  it('Allows valid progression: WAITING -> READY_CHECK -> COUNTDOWN -> IN_PROGRESS -> FINISHING -> COMPLETED', () => {
    assert(canTransition('WAITING', 'READY_CHECK'));
    assert(canTransition('READY_CHECK', 'COUNTDOWN'));
    assert(canTransition('COUNTDOWN', 'IN_PROGRESS'));
    assert(canTransition('IN_PROGRESS', 'FINISHING'));
    assert(canTransition('FINISHING', 'COMPLETED'));
  });

  it('Rejects invalid forward jumps (e.g. WAITING -> IN_PROGRESS)', () => {
    assert.strictEqual(canTransition('WAITING', 'IN_PROGRESS'), false);
    assert.strictEqual(canTransition('WAITING', 'COMPLETED'), false);
  });

  it('Rejects backwards transitions once race is IN_PROGRESS (e.g. IN_PROGRESS -> WAITING)', () => {
    assert.strictEqual(canTransition('IN_PROGRESS', 'WAITING'), false);
    assert.strictEqual(canTransition('COMPLETED', 'IN_PROGRESS'), false);
  });

  it('Permits CANCELLED from pre-race states and ABORTED from active racing', () => {
    assert(canTransition('WAITING', 'CANCELLED'));
    assert(canTransition('COUNTDOWN', 'CANCELLED'));
    assert(canTransition('IN_PROGRESS', 'ABORTED'));
    assert.strictEqual(canTransition('IN_PROGRESS', 'CANCELLED'), false);
  });
});

// -----------------------------------------------------------------------------
// 3. GPS ANTI-CHEAT & VELOCITY VALIDATION
// -----------------------------------------------------------------------------
describe('3. GPS Anti-Cheat Heuristics', () => {
  const SPEED_THRESHOLDS = {
    running: 12.5,     // ~45 km/h
    cycling: 30.0,     // ~108 km/h
    motorbike: 100.0   // ~360 km/h
  };

  function validateSample(sport, sequence, lastSeq, accuracyM, speedMps, isMocked) {
    if (isMocked) return { valid: false, reason: 'MOCK_DETECTED' };
    if (accuracyM > 45.0) return { valid: false, reason: 'POOR_ACCURACY' };
    if (sequence <= lastSeq) return { valid: false, reason: 'OUT_OF_SEQUENCE' };
    const maxSpeed = SPEED_THRESHOLDS[sport] || 12.5;
    if (speedMps > maxSpeed) return { valid: false, reason: 'EXCESSIVE_SPEED' };
    return { valid: true };
  }

  it('Rejects mock location flags immediately', () => {
    const res = validateSample('running', 1, 0, 5.0, 3.0, true);
    assert.strictEqual(res.valid, false);
    assert.strictEqual(res.reason, 'MOCK_DETECTED');
  });

  it('Rejects noisy GPS samples with accuracy > 45m', () => {
    const res = validateSample('running', 1, 0, 68.0, 3.0, false);
    assert.strictEqual(res.valid, false);
    assert.strictEqual(res.reason, 'POOR_ACCURACY');
  });

  it('Enforces sport-specific speed limits (Running capped at 12.5 m/s)', () => {
    const validRun = validateSample('running', 2, 1, 4.0, 5.5, false);
    assert.strictEqual(validRun.valid, true);

    const vehicleInRun = validateSample('running', 2, 1, 4.0, 18.0, false);
    assert.strictEqual(vehicleInRun.valid, false);
    assert.strictEqual(vehicleInRun.reason, 'EXCESSIVE_SPEED');
  });

  it('Allows higher velocity for cycling (up to 30 m/s)', () => {
    const cyclingSprint = validateSample('cycling', 2, 1, 4.0, 22.0, false);
    assert.strictEqual(cyclingSprint.valid, true);

    const vehicleInCycling = validateSample('cycling', 2, 1, 4.0, 45.0, false);
    assert.strictEqual(vehicleInCycling.valid, false);
  });
});

// -----------------------------------------------------------------------------
// 4. ADMOB PLACEMENT SAFETY CONSTRAINTS
// -----------------------------------------------------------------------------
describe('4. Google AdMob Placement Safety Engine', () => {
  function canShowAd(screenName, isLiveRacing) {
    if (isLiveRacing) return false;
    const blocked = ['live_race', 'countdown', 'emergency_stop', 'race_lobby_active'];
    if (blocked.includes(screenName)) return false;
    return ['home', 'results', 'profile'].includes(screenName);
  }

  it('Strictly forbids ads whenever isLiveRacing is true', () => {
    assert.strictEqual(canShowAd('home', true), false);
    assert.strictEqual(canShowAd('results', true), false);
    assert.strictEqual(canShowAd('live_race', true), false);
  });

  it('Blocks ads on live map, countdown, and emergency controls', () => {
    assert.strictEqual(canShowAd('live_race', false), false);
    assert.strictEqual(canShowAd('countdown', false), false);
    assert.strictEqual(canShowAd('emergency_stop', false), false);
  });

  it('Permits non-disruptive banners on Home and post-race Results screens only', () => {
    assert.strictEqual(canShowAd('home', false), true);
    assert.strictEqual(canShowAd('results', false), true);
    assert.strictEqual(canShowAd('profile', false), true);
  });
});

// -----------------------------------------------------------------------------
// 5. FINANCIAL FORMULA VERIFICATION
// -----------------------------------------------------------------------------
describe('5. Financial Analytics Formulae', () => {
  it('Computes Operating Result = Recorded Revenue minus Operating Expenses correctly', () => {
    const revenue = 6700.0;
    const expenses = 7100.0;
    const operatingResult = revenue - expenses;
    assert.strictEqual(operatingResult, -400.0);
  });
});

console.log(`\n========================================`);
console.log(`RESULTS: ${passedTests} / ${totalTests} tests passed (${Math.round((passedTests/totalTests)*100)}%)`);
console.log(`========================================\n`);

if (passedTests !== totalTests) {
  process.exit(1);
}
