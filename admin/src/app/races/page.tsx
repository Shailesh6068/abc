'use client';

import React, { useState } from 'react';
import { Flag, ShieldAlert, CheckCircle, Search, Eye, AlertTriangle } from 'lucide-react';
import { useAdminAuth } from '@/lib/auth-context';

interface RaceRecord {
  id: string;
  creator: string;
  sport: 'running' | 'cycling' | 'motorbike';
  mode: string;
  participantsCount: number;
  status: string;
  validationStatus: 'valid' | 'flagged_review' | 'disqualified';
  startTime: string;
  flagReason?: string;
}

export default function RaceManagementPage() {
  const { hasRole } = useAdminAuth();
  const [selectedRace, setSelectedRace] = useState<RaceRecord | null>(null);
  const [inspectModalOpen, setInspectModalOpen] = useState(false);

  const [races, setRaces] = useState<RaceRecord[]>([
    {
      id: 'race-901',
      creator: 'AeroStride',
      sport: 'running',
      mode: 'distance_race (1K)',
      participantsCount: 4,
      status: 'COMPLETED',
      validationStatus: 'valid',
      startTime: '2026-10-17 12:45',
    },
    {
      id: 'race-902',
      creator: 'TrackCheetah',
      sport: 'running',
      mode: 'time_trial (10m)',
      participantsCount: 2,
      status: 'COMPLETED',
      validationStatus: 'flagged_review',
      startTime: '2026-10-17 11:20',
      flagReason: 'Teleportation jump: 340m delta in 1.4s (speed ~874 km/h)',
    },
    {
      id: 'race-903',
      creator: 'NeonRider',
      sport: 'motorbike',
      mode: 'head_to_head',
      participantsCount: 2,
      status: 'IN_PROGRESS',
      validationStatus: 'valid',
      startTime: '2026-10-17 13:40',
    },
    {
      id: 'race-904',
      creator: 'VelocityPhantom',
      sport: 'cycling',
      mode: 'distance_race (5K)',
      participantsCount: 6,
      status: 'COMPLETED',
      validationStatus: 'valid',
      startTime: '2026-10-16 18:15',
    },
  ]);

  const canManageRaces = hasRole(['super_admin', 'operations_admin', 'moderator']);

  const handleCorrectResult = (newStatus: 'valid' | 'disqualified') => {
    if (!selectedRace) return;
    setRaces((prev) =>
      prev.map((r) =>
        r.id === selectedRace.id ? { ...r, validationStatus: newStatus } : r
      )
    );
    alert(`Race ${selectedRace.id} validation status updated to ${newStatus}. Audit event recorded.`);
    setInspectModalOpen(false);
    setSelectedRace(null);
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-black text-white">RACE OPERATIONS & GPS ANTI-CHEAT REVIEW</h1>
        <p className="text-sm text-slate-400 mt-1">
          Monitor real-time racing stages, inspect telemetry anomalies, and adjudicate disputes.
        </p>
      </div>

      {/* Races Table */}
      <div className="bg-[#131b2e] rounded-2xl border border-[#1e2a47] overflow-hidden">
        <table className="w-full text-left text-sm">
          <thead className="bg-[#0d1424] text-slate-400 text-xs font-semibold uppercase tracking-wider border-b border-[#1e2a47]">
            <tr>
              <th className="px-6 py-4">Race ID</th>
              <th className="px-6 py-4">Sport & Mode</th>
              <th className="px-6 py-4">Creator</th>
              <th className="px-6 py-4">Racers</th>
              <th className="px-6 py-4">Status</th>
              <th className="px-6 py-4">Anti-Cheat Verdict</th>
              <th className="px-6 py-4 text-right">Inspect</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[#1e2a47]">
            {races.map((race) => (
              <tr key={race.id} className="hover:bg-[#16223b] transition-colors">
                <td className="px-6 py-4 font-mono font-bold text-white">{race.id}</td>
                <td className="px-6 py-4">
                  <span className="capitalize font-semibold text-white">{race.sport}</span>
                  <p className="text-xs text-slate-400">{race.mode}</p>
                </td>
                <td className="px-6 py-4 text-slate-300">{race.creator}</td>
                <td className="px-6 py-4 font-mono">{race.participantsCount}</td>
                <td className="px-6 py-4">
                  <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-bold font-mono uppercase bg-[#1e2a47] text-slate-300">
                    {race.status}
                  </span>
                </td>
                <td className="px-6 py-4">
                  {race.validationStatus === 'valid' ? (
                    <span className="inline-flex items-center text-xs text-[#00e676] font-semibold">
                      <CheckCircle className="w-3.5 h-3.5 mr-1" /> Validated Clean
                    </span>
                  ) : (
                    <span className="inline-flex items-center text-xs text-amber-400 font-bold px-2 py-0.5 rounded bg-amber-500/10 border border-amber-500/30">
                      <ShieldAlert className="w-3.5 h-3.5 mr-1 text-amber-400" /> FLAGGED REVIEW
                    </span>
                  )}
                </td>
                <td className="px-6 py-4 text-right">
                  <button
                    onClick={() => {
                      setSelectedRace(race);
                      setInspectModalOpen(true);
                    }}
                    className="p-1.5 rounded-lg bg-[#1e2a47] hover:bg-[#00e676]/20 hover:text-[#00e676] text-slate-400 transition-colors"
                  >
                    <Eye className="w-4 h-4" />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Telemetry Inspection & Anti-Cheat Review Modal */}
      {inspectModalOpen && selectedRace && (
        <div className="fixed inset-0 bg-black/80 flex items-center justify-center p-4 z-50">
          <div className="bg-[#131b2e] border border-[#1e2a47] rounded-2xl p-6 max-w-xl w-full space-y-4">
            <div className="flex items-center justify-between border-b border-[#1e2a47] pb-3">
              <h3 className="text-lg font-bold text-white flex items-center space-x-2">
                <span>GPS Telemetry Audit: {selectedRace.id}</span>
              </h3>
              <span className="text-xs font-mono uppercase text-[#00e5ff]">{selectedRace.sport}</span>
            </div>

            <div className="space-y-3 text-xs text-slate-300">
              <div className="bg-[#0d1424] p-3 rounded-xl border border-[#1e2a47] space-y-1">
                <p><span className="text-slate-400">Host:</span> {selectedRace.creator}</p>
                <p><span className="text-slate-400">Scheduled Start:</span> {selectedRace.startTime}</p>
                <p><span className="text-slate-400">Status:</span> {selectedRace.status}</p>
              </div>

              {selectedRace.flagReason && (
                <div className="bg-amber-500/10 border border-amber-500/30 p-3 rounded-xl text-amber-300">
                  <p className="font-bold flex items-center">
                    <AlertTriangle className="w-4 h-4 mr-1 text-amber-400" />
                    ANTI-CHEAT HEURISTIC TRIGGERED
                  </p>
                  <p className="mt-1 text-xs">{selectedRace.flagReason}</p>
                </div>
              )}

              <div className="bg-[#0d1424] p-3 rounded-xl border border-[#1e2a47]">
                <h4 className="font-bold text-white mb-2">Sample Sequence Stream (Last 4 Coordinates)</h4>
                <div className="space-y-1 font-mono text-[11px] text-slate-400">
                  <p>seq #142: 13.04752 N, 80.28251 E | Acc: 3.8m | Vel: 4.8 m/s [VALID]</p>
                  <p>seq #143: 13.04758 N, 80.28259 E | Acc: 4.1m | Vel: 5.1 m/s [VALID]</p>
                  <p className={selectedRace.flagReason ? 'text-amber-400 font-bold' : ''}>
                    seq #144: 13.05120 N, 80.28410 E | Acc: 4.0m | Vel: 242.8 m/s [JUMP DETECTED]
                  </p>
                </div>
              </div>
            </div>

            {canManageRaces && (
              <div className="flex justify-between items-center pt-3 border-t border-[#1e2a47]">
                <button
                  onClick={() => handleCorrectResult('disqualified')}
                  className="px-4 py-2 bg-red-600 hover:bg-red-500 text-white rounded-xl text-xs font-bold"
                >
                  Disqualify Competitor
                </button>
                <div className="flex space-x-2">
                  <button
                    onClick={() => setInspectModalOpen(false)}
                    className="px-4 py-2 bg-[#0d1424] text-slate-400 hover:text-white rounded-xl text-xs font-semibold"
                  >
                    Close
                  </button>
                  <button
                    onClick={() => handleCorrectResult('valid')}
                    className="px-4 py-2 bg-[#00e676] hover:bg-[#00c853] text-slate-900 rounded-xl text-xs font-bold"
                  >
                    Confirm Valid Result
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
