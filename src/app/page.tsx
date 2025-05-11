'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

export default function HomePage() {
  const router = useRouter();

  useEffect(() => {
    const days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
    // Conditional logic to avoid window usage during server rendering / pre-rendering
    if (typeof window !== 'undefined') {
      const currentDayIndex = new Date().getDay();
      const currentDayId = days[currentDayIndex];
      router.replace(`/workout/${currentDayId}`);
    } else {
      // Fallback for server-side rendering, or if window is not available
      router.replace('/workout/monday');
    }
  }, [router]);

  return (
    <div className="flex h-screen items-center justify-center">
      <p>Loading your workout...</p>
    </div>
  );
}
