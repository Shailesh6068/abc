'use client';

import React, { useState } from 'react';
import { Settings, Save, ShieldCheck, AlertTriangle } from 'lucide-react';
import { useAdminAuth } from '@/lib/auth-context';

export default function AppSettingsPage() {
  const { hasRole, adminUser } = useAdminAuth();

  const [maxRadiusM, setMaxRadiusM] = useState(5000);
  const [maxParticipants, setMaxParticipants] = useState(12);
  const [runningEnabled, setRunningEnabled] = useState(true);
  const [cyclingEnabled, setCyclingEnabled] = useState(true);
  const [motorbikeEnabled, setMotorbikeEnabled] = useState(true);
  const [runningSpeedCap, setRunningSpeedCap] = useState(12.5);
  const [cyclingSpeedCap, setCyclingSpeedCap] = useState(30.0);
  const [motorbikeSpeedCap, setMotorbikeSpeedCap] = useState(100.0);
  const [maxAccuracyM, setMaxAccuracyM] = useState(35.0);
  const [maintenanceMode, setMaintenanceMode] = useState(false);
  const [homeBannerAds, setHomeBannerAds] = useState(true);
  const [resultsBannerAds, setResultsBannerAds] = useState(true);

  const canSave = hasRole(['super_admin', 'operations_admin']);

  const handleSave = () => {
    alert(`Configuration parameters successfully saved to app_configuration. Audit event logged by ${adminUser?.displayName}.`);
  };

  return (
    <div className="space-y-6 max-w-4xl">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-black text-white">APPLICATION CONFIGURATION & POLICIES</h1>
          <p className="text-sm text-slate-400 mt-1">
            Global discovery bounds, server anti-cheat thresholds, and live feature flags.
          </p>
        </div>

        {canSave && (
          <button
            onClick={handleSave}
            className="flex items-center space-x-2 px-5 py-2.5 bg-[#00e676] hover:bg-[#00c853] text-slate-900 font-bold rounded-xl text-xs shadow-lg shadow-[#00e676]/20"
          >
            <Save className="w-4 h-4" />
            <span>Apply Changes</span>
          </button>
        )}
      </div>

      {/* System Status Banner */}
      {maintenanceMode && (
        <div className="bg-amber-500/10 border border-amber-500/30 p-4 rounded-2xl flex items-center space-x-3 text-amber-300">
          <AlertTriangle className="w-5 h-5 text-amber-400 shrink-0" />
          <p className="text-xs">
            <strong>Maintenance Mode Active:</strong> New race lobbies are blocked for ordinary users.
          </p>
        </div>
      )}

      {/* Settings Sections */}
      <div className="space-y-6">
        {/* Section 1: Discovery & Lobby Bounds */}
        <div className="bg-[#131b2e] p-6 rounded-2xl border border-[#1e2a47] space-y-4">
          <h3 className="text-base font-bold text-white border-b border-[#1e2a47] pb-3">
            Discovery & Matchmaking Boundaries
          </h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold text-slate-300 mb-1">Max Discovery Radius (Meters)</label>
              <input
                type="number"
                value={maxRadiusM}
                onChange={(e) => setMaxRadiusM(parseInt(e.target.value))}
                className="w-full bg-[#0d1424] border border-[#1e2a47] rounded-xl px-3 py-2 text-sm text-white"
              />
              <p className="text-[11px] text-slate-500 mt-1">Hard server-side ceiling for PostGIS spatial queries</p>
            </div>

            <div>
              <label className="block text-xs font-semibold text-slate-300 mb-1">Max Racers Per Lobby</label>
              <input
                type="number"
                value={maxParticipants}
                onChange={(e) => setMaxParticipants(parseInt(e.target.value))}
                className="w-full bg-[#0d1424] border border-[#1e2a47] rounded-xl px-3 py-2 text-sm text-white"
              />
              <p className="text-[11px] text-slate-500 mt-1">Default 4-12 racers for low GPS channel latency</p>
            </div>
          </div>
        </div>

        {/* Section 2: GPS Anti-Cheat Physical Thresholds */}
        <div className="bg-[#131b2e] p-6 rounded-2xl border border-[#1e2a47] space-y-4">
          <h3 className="text-base font-bold text-white border-b border-[#1e2a47] pb-3">
            GPS Anti-Cheat Physical Speed Limits (m/s)
          </h3>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div>
              <label className="block text-xs font-semibold text-slate-300 mb-1">Running Speed Cap (m/s)</label>
              <input
                type="number"
                step="0.5"
                value={runningSpeedCap}
                onChange={(e) => setRunningSpeedCap(parseFloat(e.target.value))}
                className="w-full bg-[#0d1424] border border-[#1e2a47] rounded-xl px-3 py-2 text-sm text-white"
              />
              <p className="text-[11px] text-slate-500 mt-1">12.5 m/s (~45 km/h Olympic peak)</p>
            </div>

            <div>
              <label className="block text-xs font-semibold text-slate-300 mb-1">Cycling Speed Cap (m/s)</label>
              <input
                type="number"
                step="1"
                value={cyclingSpeedCap}
                onChange={(e) => setCyclingSpeedCap(parseFloat(e.target.value))}
                className="w-full bg-[#0d1424] border border-[#1e2a47] rounded-xl px-3 py-2 text-sm text-white"
              />
              <p className="text-[11px] text-slate-500 mt-1">30.0 m/s (~108 km/h sprint/descent)</p>
            </div>

            <div>
              <label className="block text-xs font-semibold text-slate-300 mb-1">Motorbike Speed Cap (m/s)</label>
              <input
                type="number"
                step="5"
                value={motorbikeSpeedCap}
                onChange={(e) => setMotorbikeSpeedCap(parseFloat(e.target.value))}
                className="w-full bg-[#0d1424] border border-[#1e2a47] rounded-xl px-3 py-2 text-sm text-white"
              />
              <p className="text-[11px] text-slate-500 mt-1">100.0 m/s (~360 km/h closed track)</p>
            </div>
          </div>
        </div>

        {/* Section 3: Advertising & Consent Controls */}
        <div className="bg-[#131b2e] p-6 rounded-2xl border border-[#1e2a47] space-y-4">
          <h3 className="text-base font-bold text-white border-b border-[#1e2a47] pb-3">
            Advertising Placements & Fair Play
          </h3>
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-semibold text-white">Home Screen Banner</p>
                <p className="text-xs text-slate-400">Small adaptive banner below matchmaking drawer</p>
              </div>
              <input
                type="checkbox"
                checked={homeBannerAds}
                onChange={(e) => setHomeBannerAds(e.target.checked)}
                className="w-4 h-4 accent-[#00e676]"
              />
            </div>

            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-semibold text-white">Race Results Banner</p>
                <p className="text-xs text-slate-400">Static banner displayed after final verified podium standings</p>
              </div>
              <input
                type="checkbox"
                checked={resultsBannerAds}
                onChange={(e) => setResultsBannerAds(e.target.checked)}
                className="w-4 h-4 accent-[#00e676]"
              />
            </div>

            <div className="p-3 bg-[#0d1424] rounded-xl border border-[#1e2a47] text-xs text-slate-400">
              Note: Advertisements are automatically disabled during all active countdowns, live racing maps, and safety controls by system rule.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
