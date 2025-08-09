// src/app/workout/[day]/page.tsx
'use client'; 

import WorkoutView from '@/components/workout/workout-view';
import { use, Suspense } from 'react';
import LoadingWorkoutPage from './loading';

type WorkoutPageProps = {
  params: {
    day: string; 
  };
};

// This page is a Client Component wrapper to handle suspense
export default function WorkoutPageWrapper({ params }: WorkoutPageProps) {
  // `use` is a React hook for resolving promises. It's a clean way to handle params
  // that might be part of the dynamic route segment.
  const resolvedParams = use(params as any);

  return (
    <Suspense fallback={<LoadingWorkoutPage />}>
      <WorkoutView dayId={resolvedParams.day} />
    </Suspense>
  );
}
