import type { Metadata } from 'next';
import './globals.css';
import { AuthProvider } from '@/lib/auth-context';
import { AdminSidebar } from '@/components/layout/sidebar';
import { AdminHeader } from '@/components/layout/header';

export const metadata: Metadata = {
  title: 'RaceZone — Real-Time GPS Racing Admin Command Center',
  description: 'Enterprise operations, real-time live race telemetry, anti-cheat moderation, and financial analytics.',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body className="bg-[#090d16] text-[#f8fafc] min-h-screen">
        <AuthProvider>
          <div className="flex min-h-screen">
            <AdminSidebar />
            <div className="flex-1 flex flex-col min-w-0">
              <AdminHeader />
              <main className="flex-1 p-8 overflow-y-auto">
                {children}
              </main>
            </div>
          </div>
        </AuthProvider>
      </body>
    </html>
  );
}
