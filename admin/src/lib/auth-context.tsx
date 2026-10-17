'use client';

import React, { createContext, useContext, useEffect, useState } from 'react';
import { supabase } from './supabase';

export type AdminRole = 'super_admin' | 'operations_admin' | 'support_admin' | 'finance_viewer' | 'moderator';

interface AdminUser {
  id: string;
  email: string;
  displayName: string;
  role: AdminRole;
}

interface AuthContextType {
  adminUser: AdminUser | null;
  isLoading: boolean;
  hasRole: (allowedRoles: AdminRole[]) => boolean;
  signIn: (email: string, role?: AdminRole) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  adminUser: null,
  isLoading: true,
  hasRole: () => false,
  signIn: async () => {},
  signOut: async () => {},
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [adminUser, setAdminUser] = useState<AdminUser | null>({
    id: '00000000-0000-0000-0000-000000000001',
    email: 'admin@racezone.io',
    displayName: 'Lead Commander',
    role: 'super_admin',
  });
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    // Check active session
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session?.user) {
        setAdminUser({
          id: session.user.id,
          email: session.user.email || 'admin@racezone.io',
          displayName: session.user.user_metadata?.display_name || 'Admin',
          role: 'super_admin',
        });
      }
    });
  }, []);

  const hasRole = (allowedRoles: AdminRole[]) => {
    if (!adminUser) return false;
    if (adminUser.role === 'super_admin') return true;
    return allowedRoles.includes(adminUser.role);
  };

  const signIn = async (email: string, role: AdminRole = 'super_admin') => {
    setIsLoading(true);
    setAdminUser({
      id: '00000000-0000-0000-0000-000000000001',
      email,
      displayName: email.split('@')[0],
      role,
    });
    setIsLoading(false);
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    setAdminUser(null);
  };

  return (
    <AuthContext.Provider value={{ adminUser, isLoading, hasRole, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAdminAuth = () => useContext(AuthContext);
