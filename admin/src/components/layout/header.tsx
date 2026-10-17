'use client';

import React from 'react';
import { Bell, ShieldCheck, LogOut } from 'lucide-react';
import { useAdminAuth, AdminRole } from '@/lib/auth-context';

export function AdminHeader() {
  const { adminUser, signIn, signOut } = useAdminAuth();

  return (
    <header className="h-16 bg-[#0d1424] border-b border-[#1e2a47] px-6 flex items-center justify-between sticky top-0 z-30">
      <div className="flex items-center space-x-3">
        <span className="flex items-center space-x-1.5 px-2.5 py-1 rounded-full bg-[#00e676]/10 text-[#00e676] text-xs font-medium border border-[#00e676]/30">
          <span className="w-1.5 h-1.5 rounded-full bg-[#00e676] animate-pulse"></span>
          <span>LIVE CLUSTER ACTIVE</span>
        </span>
        <span className="text-xs text-slate-400">PostGIS Engine • RLS Enforced</span>
      </div>

      <div className="flex items-center space-x-4">
        {/* Test Role Switcher (Simulate all 5 authorized roles) */}
        <div className="flex items-center space-x-2 bg-[#131b2e] px-2.5 py-1 rounded-lg border border-[#1e2a47]">
          <ShieldCheck className="w-3.5 h-3.5 text-[#00e5ff]" />
          <span className="text-xs text-slate-400">Role:</span>
          <select
            value={adminUser?.role || 'super_admin'}
            onChange={(e) => signIn(adminUser?.email || 'admin@racezone.io', e.target.value as AdminRole)}
            className="bg-transparent text-xs text-[#00e676] font-semibold focus:outline-none cursor-pointer"
          >
            <option value="super_admin" className="bg-[#131b2e] text-white">super_admin</option>
            <option value="operations_admin" className="bg-[#131b2e] text-white">operations_admin</option>
            <option value="support_admin" className="bg-[#131b2e] text-white">support_admin</option>
            <option value="finance_viewer" className="bg-[#131b2e] text-white">finance_viewer</option>
            <option value="moderator" className="bg-[#131b2e] text-white">moderator</option>
          </select>
        </div>

        <button className="p-2 rounded-xl text-slate-400 hover:text-white hover:bg-[#152038] relative">
          <Bell className="w-4 h-4" />
          <span className="absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-[#00e5ff]"></span>
        </button>

        <button
          onClick={() => signOut()}
          className="p-2 rounded-xl text-slate-400 hover:text-red-400 hover:bg-[#152038] transition-colors"
          title="Sign Out"
        >
          <LogOut className="w-4 h-4" />
        </button>
      </div>
    </header>
  );
}
