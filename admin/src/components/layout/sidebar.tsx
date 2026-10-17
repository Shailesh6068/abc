'use client';

import React from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  LayoutDashboard,
  Users,
  Flag,
  ShieldAlert,
  DollarSign,
  Settings,
  Zap,
} from 'lucide-react';
import { useAdminAuth } from '@/lib/auth-context';

export function AdminSidebar() {
  const pathname = usePathname();
  const { adminUser, hasRole } = useAdminAuth();

  const navItems = [
    { href: '/', label: 'Overview', icon: LayoutDashboard, roles: ['super_admin', 'operations_admin', 'support_admin', 'finance_viewer', 'moderator'] },
    { href: '/users', label: 'User Directory', icon: Users, roles: ['super_admin', 'operations_admin', 'support_admin'] },
    { href: '/races', label: 'Race Control', icon: Flag, roles: ['super_admin', 'operations_admin', 'moderator'] },
    { href: '/moderation', label: 'Moderation Queue', icon: ShieldAlert, roles: ['super_admin', 'operations_admin', 'support_admin', 'moderator'] },
    { href: '/finance', label: 'Finance & Analytics', icon: DollarSign, roles: ['super_admin', 'operations_admin', 'finance_viewer'] },
    { href: '/settings', label: 'Configuration', icon: Settings, roles: ['super_admin', 'operations_admin'] },
  ];

  return (
    <aside className="w-64 bg-[#0d1424] border-r border-[#1e2a47] flex flex-col h-screen sticky top-0">
      {/* Brand Header */}
      <div className="p-6 border-b border-[#1e2a47] flex items-center space-x-3">
        <div className="w-9 h-9 rounded-xl bg-[#00e676]/20 border border-[#00e676]/50 flex items-center justify-center">
          <Zap className="w-5 h-5 text-[#00e676]" />
        </div>
        <div>
          <h1 className="text-base font-bold text-white tracking-wide">RaceZone</h1>
          <p className="text-xs text-[#00e5ff] font-semibold tracking-wider">COMMAND CENTER</p>
        </div>
      </div>

      {/* Nav List */}
      <nav className="flex-1 p-4 space-y-1.5 overflow-y-auto">
        {navItems.map((item) => {
          if (!hasRole(item.roles as any)) return null;
          const isActive = pathname === item.href;
          const Icon = item.icon;

          return (
            <Link
              key={item.href}
              href={item.href}
              className={`flex items-center space-x-3 px-3.5 py-2.5 rounded-xl text-sm font-medium transition-all ${
                isActive
                  ? 'bg-[#00e676]/15 text-[#00e676] border border-[#00e676]/30 font-semibold'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-[#152038]'
              }`}
            >
              <Icon className={`w-4 h-4 ${isActive ? 'text-[#00e676]' : 'text-slate-400'}`} />
              <span>{item.label}</span>
            </Link>
          );
        })}
      </nav>

      {/* Admin User Card */}
      <div className="p-4 border-t border-[#1e2a47]">
        <div className="bg-[#131b2e] p-3 rounded-xl border border-[#1e2a47] flex items-center space-x-3">
          <div className="w-8 h-8 rounded-full bg-[#00e676] text-slate-900 font-bold flex items-center justify-center text-xs">
            {adminUser?.displayName.charAt(0).toUpperCase() || 'A'}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-xs font-semibold text-white truncate">{adminUser?.displayName}</p>
            <p className="text-[10px] text-[#00e676] uppercase tracking-wider font-mono">{adminUser?.role.replace('_', ' ')}</p>
          </div>
        </div>
      </div>
    </aside>
  );
}
