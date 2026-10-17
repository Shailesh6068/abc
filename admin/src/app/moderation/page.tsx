'use client';

import React, { useState } from 'react';
import { ShieldAlert, CheckCircle, Clock, XCircle, User, Flag } from 'lucide-react';
import { useAdminAuth } from '@/lib/auth-context';

interface ReportItem {
  id: string;
  reporter: string;
  reportedUser?: string;
  raceId?: string;
  category: string;
  description: string;
  status: 'OPEN' | 'UNDER_REVIEW' | 'RESOLVED' | 'DISMISSED';
  createdAt: string;
  resolution?: string;
}

export default function ModerationQueuePage() {
  const { hasRole, adminUser } = useAdminAuth();
  const [reports, setReports] = useState<ReportItem[]>([
    {
      id: 'rep-01',
      reporter: 'VelocityPhantom',
      reportedUser: 'TrackCheetah',
      raceId: 'race-902',
      category: 'GPS Cheating / Spoofing',
      description: 'Competitor jumped 350m ahead on the final corner during time trial, impossible sprint speed.',
      status: 'OPEN',
      createdAt: '2026-10-17 11:35',
    },
    {
      id: 'rep-02',
      reporter: 'UrbanRider',
      reportedUser: 'SpeedMonster99',
      category: 'Unsafe Racing / Traffic Infraction',
      description: 'Racer was livestreaming competitive speeding on a congested city road instead of an approved track.',
      status: 'UNDER_REVIEW',
      createdAt: '2026-10-16 19:10',
    },
    {
      id: 'rep-03',
      reporter: 'TrailBlazer',
      reportedUser: 'AnonymousBot',
      category: 'Fake Account / Bot',
      description: 'Account pinging discovery every 500ms with synthetic stationary coordinates.',
      status: 'RESOLVED',
      createdAt: '2026-10-15 14:20',
      resolution: 'Account suspended and presence heartbeat blocked by operations team.',
    },
  ]);

  const [activeReport, setActiveReport] = useState<ReportItem | null>(null);
  const [resolutionText, setResolutionText] = useState('');

  const canModerate = hasRole(['super_admin', 'operations_admin', 'moderator']);

  const handleUpdateStatus = (newStatus: 'UNDER_REVIEW' | 'RESOLVED' | 'DISMISSED') => {
    if (!activeReport) return;

    setReports((prev) =>
      prev.map((r) =>
        r.id === activeReport.id
          ? {
              ...r,
              status: newStatus,
              resolution: resolutionText.trim() || r.resolution,
            }
          : r
      )
    );

    alert(`Report ${activeReport.id} transitioned to ${newStatus}. Adjudicated by ${adminUser?.displayName}.`);
    setActiveReport(null);
    setResolutionText('');
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-black text-white">COMMUNITY SAFETY & DISPUTE MODERATION</h1>
        <p className="text-sm text-slate-400 mt-1">
          Review community incident reports, anti-cheat flags, and fair-play violations.
        </p>
      </div>

      {/* Reports List */}
      <div className="grid grid-cols-1 gap-4">
        {reports.map((report) => (
          <div
            key={report.id}
            className="bg-[#131b2e] border border-[#1e2a47] rounded-2xl p-5 hover:border-[#2a3b63] transition-colors"
          >
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-[#1e2a47] pb-3 mb-3">
              <div className="flex items-center space-x-3">
                <span className="text-xs font-mono font-bold text-white bg-[#0d1424] px-2.5 py-1 rounded-lg border border-[#1e2a47]">
                  {report.id}
                </span>
                <span className="text-xs font-bold px-2 py-0.5 rounded bg-red-500/10 text-red-400 border border-red-500/30">
                  {report.category}
                </span>
                <span className="text-xs text-slate-400">Filed {report.createdAt}</span>
              </div>

              <span
                className={`text-xs font-bold uppercase tracking-wider px-2.5 py-1 rounded-full ${
                  report.status === 'OPEN'
                    ? 'bg-amber-500/10 text-amber-400 border border-amber-500/30'
                    : report.status === 'UNDER_REVIEW'
                    ? 'bg-blue-500/10 text-blue-400 border border-blue-500/30'
                    : report.status === 'RESOLVED'
                    ? 'bg-[#00e676]/10 text-[#00e676] border border-[#00e676]/30'
                    : 'bg-slate-500/10 text-slate-400 border border-slate-500/30'
                }`}
              >
                {report.status}
              </span>
            </div>

            <p className="text-sm text-slate-200 mb-3">{report.description}</p>

            <div className="flex flex-wrap items-center justify-between gap-3 text-xs text-slate-400">
              <div className="flex items-center space-x-4">
                <span>Reporter: <strong className="text-white">{report.reporter}</strong></span>
                {report.reportedUser && (
                  <span>Reported Racer: <strong className="text-red-400">{report.reportedUser}</strong></span>
                )}
                {report.raceId && (
                  <span>Race Ref: <strong className="text-[#00e5ff]">{report.raceId}</strong></span>
                )}
              </div>

              {canModerate && (
                <button
                  onClick={() => {
                    setActiveReport(report);
                    setResolutionText(report.resolution || '');
                  }}
                  className="px-3.5 py-1.5 rounded-xl bg-[#00e676]/15 text-[#00e676] hover:bg-[#00e676]/25 font-bold"
                >
                  Adjudicate Incident
                </button>
              )}
            </div>

            {report.resolution && (
              <div className="mt-3 bg-[#0d1424] p-3 rounded-xl border border-[#1e2a47] text-xs text-slate-300">
                <span className="font-semibold text-[#00e676]">Resolution Record:</span> {report.resolution}
              </div>
            )}
          </div>
        ))}
      </div>

      {/* Adjudication Modal */}
      {activeReport && (
        <div className="fixed inset-0 bg-black/80 flex items-center justify-center p-4 z-50">
          <div className="bg-[#131b2e] border border-[#1e2a47] rounded-2xl p-6 max-w-lg w-full space-y-4">
            <h3 className="text-lg font-bold text-white">Adjudicate Incident: {activeReport.id}</h3>
            <p className="text-xs text-slate-300">Category: {activeReport.category}</p>
            <p className="text-xs bg-[#0d1424] p-3 rounded-xl border border-[#1e2a47] text-slate-300">
              {activeReport.description}
            </p>

            <div>
              <label className="block text-xs font-semibold text-slate-400 mb-1">Resolution Summary & Action Notes</label>
              <textarea
                value={resolutionText}
                onChange={(e) => setResolutionText(e.target.value)}
                placeholder="Enter actions taken (e.g., GPS telemetry reviewed, verified 1st place result disqualified, racer issued 7-day warning)..."
                className="w-full bg-[#0d1424] border border-[#1e2a47] rounded-xl p-3 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-[#00e676] h-24"
              />
            </div>

            <div className="flex justify-between items-center pt-2">
              <button
                onClick={() => handleUpdateStatus('UNDER_REVIEW')}
                className="px-3 py-2 bg-blue-500/20 text-blue-400 border border-blue-500/40 rounded-xl text-xs font-bold"
              >
                Mark Under Review
              </button>
              <div className="flex space-x-2">
                <button
                  onClick={() => handleUpdateStatus('DISMISSED')}
                  className="px-3 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-xl text-xs font-bold"
                >
                  Dismiss
                </button>
                <button
                  onClick={() => handleUpdateStatus('RESOLVED')}
                  disabled={!resolutionText.trim()}
                  className="px-4 py-2 bg-[#00e676] hover:bg-[#00c853] text-slate-900 rounded-xl text-xs font-bold disabled:opacity-50"
                >
                  Resolve Incident
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
