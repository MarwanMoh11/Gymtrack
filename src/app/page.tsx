'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

export default function HomePage() {
  const router = useRouter();

  useEffect(() => {
    // Redirect unauthenticated users to the login page
    router.replace('/login');
  }, [router]);

  return (
    <div className="flex h-screen items-center justify-center bg-background">
      <p className="text-foreground">Loading...</p>
    </div>
  );
}
