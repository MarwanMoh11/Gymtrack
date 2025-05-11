'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

export default function HomePage() {
  const router = useRouter();

  useEffect(() => {
    // Redirect to the new "Today's Session" dashboard page
    router.replace('/dashboard/today');
  }, [router]);

  return (
    <div className="flex h-screen items-center justify-center">
      <p>Loading your workout dashboard...</p>
    </div>
  );
}
