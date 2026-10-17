'use client';

import React, { useState } from 'react';
import {
  DollarSign,
  TrendingUp,
  Download,
  PlusCircle,
  FileText,
  Calendar,
  CreditCard,
  PieChart as PieIcon,
  CheckCircle2,
} from 'lucide-react';
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  PieChart,
  Pie,
  Cell,
} from 'recharts';
import { useAdminAuth } from '@/lib/auth-context';

interface ExpenseItem {
  id: string;
  category: string;
  description: string;
  amount: number;
  currency: string;
  expenseDate: string;
  vendor: string;
  paymentStatus: 'paid' | 'pending' | 'cancelled';
  recurring: boolean;
}

interface RevenueItem {
  id: string;
  source: string;
  provider: string;
  amount: number;
  currency: string;
  recordType: 'recognized' | 'estimated' | 'accrued';
  externalRef: string;
  recordedAt: string;
}

export default function FinanceDashboardPage() {
  const { hasRole } = useAdminAuth();

  const [expenses, setExpenses] = useState<ExpenseItem[]>([
    {
      id: 'exp-01',
      category: 'Supabase and backend hosting',
      description: 'Supabase Pro Tier database & compute clusters',
      amount: 2200.0,
      currency: 'INR',
      expenseDate: '2026-10-02',
      vendor: 'Supabase Inc',
      paymentStatus: 'paid',
      recurring: true,
    },
    {
      id: 'exp-02',
      category: 'Maps API',
      description: 'Google Maps Platform Geocoding & Tiles quota',
      amount: 1450.0,
      currency: 'INR',
      expenseDate: '2026-10-07',
      vendor: 'Google Cloud India',
      paymentStatus: 'paid',
      recurring: false,
    },
    {
      id: 'exp-03',
      category: 'Storage and networking',
      description: 'Cloud storage & CDN egress for avatars and assets',
      amount: 680.0,
      currency: 'INR',
      expenseDate: '2026-10-09',
      vendor: 'Cloudflare',
      paymentStatus: 'paid',
      recurring: true,
    },
    {
      id: 'exp-04',
      category: 'Apple and Google developer accounts',
      description: 'Annual Developer Program licenses allocation',
      amount: 1850.0,
      currency: 'INR',
      expenseDate: '2026-09-22',
      vendor: 'Apple / Google',
      paymentStatus: 'paid',
      recurring: false,
    },
    {
      id: 'exp-05',
      category: 'Software subscriptions',
      description: 'Monitoring and log aggregator tools',
      amount: 920.0,
      currency: 'INR',
      expenseDate: '2026-10-12',
      vendor: 'Datadog',
      paymentStatus: 'paid',
      recurring: true,
    },
  ]);

  const [revenues, setRevenues] = useState<RevenueItem[]>([
    {
      id: 'rev-01',
      source: 'admob',
      provider: 'Google AdMob',
      amount: 3800.0,
      currency: 'INR',
      recordType: 'recognized',
      externalRef: 'ADMOB-SETTLEMENT-2026-09',
      recordedAt: '2026-10-05',
    },
    {
      id: 'rev-02',
      source: 'admob',
      provider: 'Google AdMob',
      amount: 1250.0,
      currency: 'INR',
      recordType: 'estimated',
      externalRef: 'ADMOB-EST-2026-10-W1',
      recordedAt: '2026-10-13',
    },
    {
      id: 'rev-03',
      source: 'admob',
      provider: 'Google AdMob',
      amount: 1650.0,
      currency: 'INR',
      recordType: 'estimated',
      externalRef: 'ADMOB-EST-2026-10-W2',
      recordedAt: '2026-10-16',
    },
  ]);

  const [isModalOpen, setIsModalOpen] = useState(false);
  const [newCategory, setNewCategory] = useState('Maps API');
  const [newDesc, setNewDesc] = useState('');
  const [newAmount, setNewAmount] = useState('');
  const [newVendor, setNewVendor] = useState('');

  const canEditFinance = hasRole(['super_admin', 'finance_viewer']);

  // Financial KPI calculations
  const totalOperatingExpenses = expenses.reduce((sum, e) => sum + e.amount, 0);
  const totalRecordedRevenue = revenues.reduce((sum, r) => sum + r.amount, 0);
  const recognizedRevenue = revenues
    .filter((r) => r.recordType === 'recognized')
    .reduce((sum, r) => sum + r.amount, 0);
  const estimatedAdmobRevenue = revenues
    .filter((r) => r.recordType === 'estimated')
    .reduce((sum, r) => sum + r.amount, 0);

  const operatingResult = totalRecordedRevenue - totalOperatingExpenses;

  // Chart data
  const expenseBreakdown = [
    { name: 'Supabase & Hosting', value: 2200, color: '#00e676' },
    { name: 'Google Maps API', value: 1450, color: '#00e5ff' },
    { name: 'Dev Licenses', value: 1850, color: '#7c4dff' },
    { name: 'Storage & CDN', value: 680, color: '#ffab00' },
    { name: 'Software Subs', value: 920, color: '#ff1744' },
  ];

  const handleAddExpense = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newDesc || !newAmount || !newVendor) return;

    const newItem: ExpenseItem = {
      id: `exp-${Date.now().toString().slice(-4)}`,
      category: newCategory,
      description: newDesc,
      amount: parseFloat(newAmount),
      currency: 'INR',
      expenseDate: new Date().toISOString().split('T')[0],
      vendor: newVendor,
      paymentStatus: 'paid',
      recurring: false,
    };

    setExpenses([newItem, ...expenses]);
    setIsModalOpen(false);
    setNewDesc('');
    setNewAmount('');
    setNewVendor('');
  };

  const exportCSV = () => {
    const headers = 'ID,Category,Description,Amount,Currency,Vendor,Status,Date\n';
    const rows = expenses
      .map(
        (e) =>
          `"${e.id}","${e.category}","${e.description}",${e.amount},"${e.currency}","${e.vendor}","${e.paymentStatus}","${e.expenseDate}"`
      )
      .join('\n');
    const blob = new Blob([headers + rows], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `racezone-expenses-${new Date().toISOString().split('T')[0]}.csv`;
    a.click();
  };

  return (
    <div className="space-y-8">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-black text-white">OPERATING EXPENSES & FINANCIAL TELEMETRY</h1>
          <p className="text-sm text-slate-400 mt-1">
            Tracking recognized revenues, cloud infrastructure costs, and AdMob advertising settlements.
          </p>
        </div>

        <div className="flex items-center space-x-3">
          <button
            onClick={exportCSV}
            className="flex items-center space-x-2 px-3.5 py-2 bg-[#131b2e] hover:bg-[#1e2a47] text-white border border-[#1e2a47] rounded-xl text-xs font-semibold"
          >
            <Download className="w-4 h-4 text-[#00e5ff]" />
            <span>Export CSV</span>
          </button>

          {canEditFinance && (
            <button
              onClick={() => setIsModalOpen(true)}
              className="flex items-center space-x-2 px-4 py-2 bg-[#00e676] hover:bg-[#00c853] text-slate-900 rounded-xl text-xs font-bold shadow-lg shadow-[#00e676]/20"
            >
              <PlusCircle className="w-4 h-4" />
              <span>Record Expense</span>
            </button>
          )}
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        <div className="bg-[#131b2e] p-5 rounded-2xl border border-[#1e2a47]">
          <span className="text-xs font-bold text-slate-400 uppercase tracking-wider">Recorded Revenue</span>
          <h2 className="text-3xl font-black text-emerald-400 mt-2">₹{totalRecordedRevenue.toLocaleString()}</h2>
          <div className="text-xs text-slate-400 mt-2 space-y-0.5">
            <p>Settled: ₹{recognizedRevenue.toLocaleString()}</p>
            <p>AdMob Accrued: ₹{estimatedAdmobRevenue.toLocaleString()}</p>
          </div>
        </div>

        <div className="bg-[#131b2e] p-5 rounded-2xl border border-[#1e2a47]">
          <span className="text-xs font-bold text-slate-400 uppercase tracking-wider">Operating Expenses</span>
          <h2 className="text-3xl font-black text-white mt-2">₹{totalOperatingExpenses.toLocaleString()}</h2>
          <p className="text-xs text-slate-400 mt-2">Sum of recognized infrastructure expenditures</p>
        </div>

        <div className="bg-[#131b2e] p-5 rounded-2xl border border-[#1e2a47]">
          <span className="text-xs font-bold text-slate-400 uppercase tracking-wider">Operating Result</span>
          <h2 className={`text-3xl font-black mt-2 ${operatingResult >= 0 ? 'text-[#00e676]' : 'text-amber-400'}`}>
            ₹{operatingResult.toLocaleString()}
          </h2>
          <p className="text-xs text-slate-400 mt-2">Recorded Revenue minus Operating Expenses</p>
        </div>

        <div className="bg-[#131b2e] p-5 rounded-2xl border border-[#1e2a47]">
          <span className="text-xs font-bold text-slate-400 uppercase tracking-wider">AdMob Est. Run-Rate</span>
          <h2 className="text-3xl font-black text-[#00e5ff] mt-2">
            ${((estimatedAdmobRevenue / 84).toFixed(2))}
          </h2>
          <p className="text-xs text-slate-400 mt-2">Safe banner placements on Home & Results</p>
        </div>
      </div>

      {/* Breakdown Chart and Revenue Ledger */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="bg-[#131b2e] p-6 rounded-2xl border border-[#1e2a47] flex flex-col">
          <h3 className="text-base font-bold text-white mb-1">Expense Breakdown by Category</h3>
          <p className="text-xs text-slate-400 mb-4">Cloud infrastructure and service costs</p>

          <div className="h-48 my-auto">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie data={expenseBreakdown} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={45} outerRadius={70}>
                  {expenseBreakdown.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={entry.color} />
                  ))}
                </Pie>
                <Tooltip contentStyle={{ backgroundColor: '#0d1424', borderColor: '#233152', borderRadius: '8px' }} />
              </PieChart>
            </ResponsiveContainer>
          </div>

          <div className="space-y-1.5 pt-3 border-t border-[#1e2a47]">
            {expenseBreakdown.map((item) => (
              <div key={item.name} className="flex justify-between text-xs">
                <span className="text-slate-300">{item.name}</span>
                <span className="font-bold text-white">₹{item.value}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Operating Expenses Table */}
        <div className="lg:col-span-2 bg-[#131b2e] rounded-2xl border border-[#1e2a47] overflow-hidden">
          <div className="p-4 border-b border-[#1e2a47] flex justify-between items-center">
            <h3 className="text-base font-bold text-white">Operating Expense Records</h3>
            <span className="text-xs text-slate-400">{expenses.length} Records Ingested</span>
          </div>
          <table className="w-full text-left text-sm">
            <thead className="bg-[#0d1424] text-slate-400 text-xs font-semibold uppercase tracking-wider border-b border-[#1e2a47]">
              <tr>
                <th className="px-5 py-3">Category & Vendor</th>
                <th className="px-5 py-3">Description</th>
                <th className="px-5 py-3">Amount</th>
                <th className="px-5 py-3">Date</th>
                <th className="px-5 py-3">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#1e2a47]">
              {expenses.map((exp) => (
                <tr key={exp.id} className="hover:bg-[#16223b] transition-colors">
                  <td className="px-5 py-3.5">
                    <p className="font-bold text-white text-xs">{exp.category}</p>
                    <p className="text-[11px] text-[#00e5ff]">{exp.vendor}</p>
                  </td>
                  <td className="px-5 py-3.5 text-xs text-slate-300">{exp.description}</td>
                  <td className="px-5 py-3.5 font-mono font-bold text-white text-xs">
                    ₹{exp.amount.toLocaleString()}
                  </td>
                  <td className="px-5 py-3.5 text-xs text-slate-400">{exp.expenseDate}</td>
                  <td className="px-5 py-3.5">
                    <span className="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-bold uppercase bg-[#00e676]/10 text-[#00e676]">
                      {exp.paymentStatus}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Add Expense Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 bg-black/80 flex items-center justify-center p-4 z-50">
          <div className="bg-[#131b2e] border border-[#1e2a47] rounded-2xl p-6 max-w-md w-full space-y-4">
            <h3 className="text-lg font-bold text-white">Record Operating Expense</h3>
            <form onSubmit={handleAddExpense} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-400 mb-1">Expense Category</label>
                <select
                  value={newCategory}
                  onChange={(e) => setNewCategory(e.target.value)}
                  className="w-full bg-[#0d1424] border border-[#1e2a47] rounded-xl px-3 py-2 text-xs text-white"
                >
                  <option value="Supabase and backend hosting">Supabase and backend hosting</option>
                  <option value="Maps API">Maps API</option>
                  <option value="Storage and networking">Storage and networking</option>
                  <option value="Domain and SSL">Domain and SSL</option>
                  <option value="Apple and Google developer accounts">Apple and Google developer accounts</option>
                  <option value="Software subscriptions">Software subscriptions</option>
                  <option value="Marketing">Marketing</option>
                  <option value="Development">Development</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-400 mb-1">Vendor / Payee</label>
                <input
                  type="text"
                  value={newVendor}
                  onChange={(e) => setNewVendor(e.target.value)}
                  placeholder="e.g. Google Cloud, AWS, Datadog"
                  className="w-full bg-[#0d1424] border border-[#1e2a47] rounded-xl px-3 py-2 text-xs text-white"
                  required
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-400 mb-1">Amount (INR)</label>
                <input
                  type="number"
                  step="0.01"
                  value={newAmount}
                  onChange={(e) => setNewAmount(e.target.value)}
                  placeholder="e.g. 1500.00"
                  className="w-full bg-[#0d1424] border border-[#1e2a47] rounded-xl px-3 py-2 text-xs text-white"
                  required
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-400 mb-1">Description</label>
                <input
                  type="text"
                  value={newDesc}
                  onChange={(e) => setNewDesc(e.target.value)}
                  placeholder="e.g. Monthly server capacity expansion"
                  className="w-full bg-[#0d1424] border border-[#1e2a47] rounded-xl px-3 py-2 text-xs text-white"
                  required
                />
              </div>

              <div className="flex justify-end space-x-3 pt-3">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="px-4 py-2 bg-[#0d1424] text-slate-400 hover:text-white rounded-xl text-xs font-semibold"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-4 py-2 bg-[#00e676] hover:bg-[#00c853] text-slate-900 rounded-xl text-xs font-bold"
                >
                  Save Record
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
