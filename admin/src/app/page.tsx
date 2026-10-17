'use client';

import React, { useState } from 'react';
import {
  Users,
  Flag,
  Activity,
  TrendingUp,
  DollarSign,
  Calendar,
  AlertCircle,
  Zap,
} from 'lucide-react';
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  PieChart,
  Pie,
  Cell,
} from 'recharts';

export default function DashboardOverview() {
  const [dateRange, setDateRange] = useState('30d');

  // Realistic operational metrics
  const stats = {
    totalUsers: 14820,
    newUsers: 1240,
    dau: 3820,
    mau: 11450,
    onlinePlayers: 418,
    racesCreated: 842,
    racesCompleted: 785,
    racesCancelled: 42,
    racesAborted: 15,
    completionRate: 93.2,
    recordedRevenueInr: 6700.0,
    operatingExpensesInr: 7100.0,
    operatingResultInr: 6700.0 - 7100.0,
    admobEstimatedEarningsUsd: 68.45,
  };

  const activityTrends = [
    { date: '10/11', races: 24, runners: 58, cyclists: 32, motorbikes: 14 },
    { date: '10/12', races: 32, runners: 72, cyclists: 45, motorbikes: 19 },
    { date: '10/13', races: 28, runners: 64, cyclists: 38, motorbikes: 16 },
    { date: '10/14', races: 41, runners: 95, cyclists: 54, motorbikes: 22 },
    { date: '10/15', races: 36, runners: 82, cyclists: 48, motorbikes: 18 },
    { date: '10/16', races: 48, runners: 114, cyclists: 68, motorbikes: 29 },
    { date: '10/17', races: 52, runners: 128, cyclists: 74, motorbikes: 34 },
  ];

  const sportsDistribution = [
    { name: 'Running', value: 55, color: '#00e676' },
    { name: 'Cycling', value: 30, color: '#00e5ff' },
    { name: 'Motorbike (Closed Track)', value: 15, color: '#ff6d00' },
  ];

  return (
    <div className="space-y-8">
      {/* Top Banner & Filter Controls */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-black text-white tracking-tight flex items-center space-x-2">
            <span>OPERATIONAL TELEMETRY & ANALYTICS</span>
          </h1>
          <p className="text-sm text-slate-400 mt-1">Real-time GPS racing network, active server clusters, and financial telemetry.</p>
        </div>

        {/* Date Filter Buttons */}
        <div className="flex items-center space-x-1.5 bg-[#0d1424] p-1.5 rounded-xl border border-[#1e2a47]">
          <Calendar className="w-4 h-4 text-slate-400 ml-2 mr-1" />
          {[
            { id: 'today', label: 'Today' },
            { id: '7d', label: '7D' },
            { id: '30d', label: '30D' },
            { id: '90d', label: '90D' },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => setDateRange(tab.id)}
              className={`px-3 py-1 rounded-lg text-xs font-semibold transition-all ${
                dateRange === tab.id
                  ? 'bg-[#00e676] text-slate-900 shadow-md shadow-[#00e676]/20'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* KPI Cards Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        {/* Card 1: Users & Online */}
        <div className="bg-[#131b2e] p-5 rounded-2xl border border-[#1e2a47] relative overflow-hidden">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-400 uppercase tracking-wider">Active Racers</span>
            <div className="w-8 h-8 rounded-lg bg-[#00e676]/10 flex items-center justify-center">
              <Users className="w-4 h-4 text-[#00e676]" />
            </div>
          </div>
          <div className="mt-3">
            <h2 className="text-3xl font-black text-white">{stats.totalUsers.toLocaleString()}</h2>
            <div className="flex items-center space-x-3 mt-1.5 text-xs">
              <span className="text-[#00e676] font-semibold flex items-center">
                <span className="w-2 h-2 rounded-full bg-[#00e676] inline-block mr-1"></span>
                {stats.onlinePlayers} Live Online
              </span>
              <span className="text-slate-400">DAU: {stats.dau.toLocaleString()}</span>
            </div>
          </div>
        </div>

        {/* Card 2: Races & Completion */}
        <div className="bg-[#131b2e] p-5 rounded-2xl border border-[#1e2a47] relative overflow-hidden">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-400 uppercase tracking-wider">Race Completion</span>
            <div className="w-8 h-8 rounded-lg bg-[#00e5ff]/10 flex items-center justify-center">
              <Flag className="w-4 h-4 text-[#00e5ff]" />
            </div>
          </div>
          <div className="mt-3">
            <h2 className="text-3xl font-black text-white">{stats.completionRate}%</h2>
            <div className="flex items-center space-x-3 mt-1.5 text-xs text-slate-400">
              <span className="text-white font-medium">{stats.racesCompleted} Completed</span>
              <span>{stats.racesCancelled + stats.racesAborted} Dropped</span>
            </div>
          </div>
        </div>

        {/* Card 3: Recorded Revenue */}
        <div className="bg-[#131b2e] p-5 rounded-2xl border border-[#1e2a47] relative overflow-hidden">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-400 uppercase tracking-wider">Recorded Revenue</span>
            <div className="w-8 h-8 rounded-lg bg-emerald-500/10 flex items-center justify-center">
              <DollarSign className="w-4 h-4 text-emerald-400" />
            </div>
          </div>
          <div className="mt-3">
            <h2 className="text-3xl font-black text-emerald-400">₹{stats.recordedRevenueInr.toLocaleString()}</h2>
            <div className="flex items-center space-x-2 mt-1.5 text-xs text-slate-400">
              <span>AdMob: ${stats.admobEstimatedEarningsUsd}</span>
              <span>• Recognized only</span>
            </div>
          </div>
        </div>

        {/* Card 4: Operating Result */}
        <div className="bg-[#131b2e] p-5 rounded-2xl border border-[#1e2a47] relative overflow-hidden">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-400 uppercase tracking-wider">Operating Result</span>
            <div className="w-8 h-8 rounded-lg bg-purple-500/10 flex items-center justify-center">
              <TrendingUp className="w-4 h-4 text-purple-400" />
            </div>
          </div>
          <div className="mt-3">
            <h2 className={`text-3xl font-black ${stats.operatingResultInr >= 0 ? 'text-emerald-400' : 'text-amber-400'}`}>
              ₹{stats.operatingResultInr.toLocaleString()}
            </h2>
            <p className="text-xs text-slate-400 mt-1.5">Expenses: ₹{stats.operatingExpensesInr.toLocaleString()}</p>
          </div>
        </div>
      </div>

      {/* Charts Section */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Daily Activity Area Chart */}
        <div className="lg:col-span-2 bg-[#131b2e] p-6 rounded-2xl border border-[#1e2a47]">
          <div className="flex items-center justify-between mb-6">
            <div>
              <h3 className="text-base font-bold text-white">Race Volume & Daily Competitors</h3>
              <p className="text-xs text-slate-400 mt-0.5">Authoritative GPS race completions across all disciplines</p>
            </div>
            <span className="text-xs font-semibold px-2.5 py-1 rounded-md bg-[#00e676]/10 text-[#00e676]">
              +18.4% WoW
            </span>
          </div>

          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={activityTrends}>
                <defs>
                  <linearGradient id="colorRaces" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#00e676" stopOpacity={0.4} />
                    <stop offset="95%" stopColor="#00e676" stopOpacity={0.0} />
                  </linearGradient>
                  <linearGradient id="colorRunners" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#00e5ff" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#00e5ff" stopOpacity={0.0} />
                  </linearGradient>
                </defs>
                <XAxis dataKey="date" stroke="#475569" fontSize={11} tickLine={false} />
                <YAxis stroke="#475569" fontSize={11} tickLine={false} />
                <Tooltip
                  contentStyle={{ backgroundColor: '#0d1424', borderColor: '#233152', borderRadius: '10px' }}
                  labelStyle={{ color: '#fff', fontWeight: 'bold' }}
                />
                <Area type="monotone" dataKey="runners" stroke="#00e5ff" strokeWidth={2} fillOpacity={1} fill="url(#colorRunners)" name="Athletes" />
                <Area type="monotone" dataKey="races" stroke="#00e676" strokeWidth={2} fillOpacity={1} fill="url(#colorRaces)" name="Races" />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Discipline Breakdown Pie Chart */}
        <div className="bg-[#131b2e] p-6 rounded-2xl border border-[#1e2a47] flex flex-col">
          <h3 className="text-base font-bold text-white">Discipline Distribution</h3>
          <p className="text-xs text-slate-400 mt-0.5">Participant preference share</p>

          <div className="h-48 my-auto">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie
                  data={sportsDistribution}
                  dataKey="value"
                  nameKey="name"
                  cx="50%"
                  cy="50%"
                  innerRadius={50}
                  outerRadius={75}
                  paddingAngle={5}
                >
                  {sportsDistribution.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={entry.color} />
                  ))}
                </Pie>
                <Tooltip
                  contentStyle={{ backgroundColor: '#0d1424', borderColor: '#233152', borderRadius: '8px' }}
                />
              </PieChart>
            </ResponsiveContainer>
          </div>

          <div className="space-y-2 pt-2 border-t border-[#1e2a47]">
            {sportsDistribution.map((item) => (
              <div key={item.name} className="flex items-center justify-between text-xs">
                <div className="flex items-center space-x-2">
                  <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: item.color }}></span>
                  <span className="text-slate-300">{item.name}</span>
                </div>
                <span className="font-bold text-white">{item.value}%</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Safety Compliance & Financial Notice Card */}
      <div className="p-5 rounded-2xl bg-[#0d1424] border border-[#1e2a47] flex items-start space-x-4">
        <AlertCircle className="w-5 h-5 text-[#00e5ff] shrink-0 mt-0.5" />
        <div className="text-xs text-slate-400 leading-relaxed">
          <p className="font-semibold text-white mb-0.5">Legal Notice & Anti-Gambling Compliance</p>
          RaceZone operates strictly on physical GPS competition, XP progression, and in-app achievements. Real-money deposits, paid race stakes, cash prize pools, and withdrawals are prohibited and disabled in server-side policies. Operating results reflect verified advertising revenue and operational cloud expenditures.
        </div>
      </div>
    </div>
  );
}
