// src/components/providers.tsx
'use client';

import { useState } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ThemeProvider } from 'next-themes';
import { AuthProvider } from '@/context/auth-context';
import { UserProvider } from '@/context/user-context';
import AppLayout from '@/components/app-layout';

export function Providers({ children }: { children: React.ReactNode }) {
  // Use useState to ensure the client is only created once on the client side.
  const [queryClient] = useState(() => new QueryClient());

  return (
    <ThemeProvider
      attribute="class"
      defaultTheme="dark"
      enableSystem
      disableTransitionOnChange
    >
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <UserProvider>
            <AppLayout>
              {children}
            </AppLayout>
          </UserProvider>
        </AuthProvider>
      </QueryClientProvider>
    </ThemeProvider>
  );
}
