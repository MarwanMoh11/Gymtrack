// src/app/dashboard/today/page.tsx
'use client';

import WorkoutView from '@/components/workout/workout-view';
import LoadingWorkoutPage from '@/app/workout/[day]/loading';
import { Suspense } from 'react';

export default function TodaysWorkoutDashboardPage() {
  return (
    <Suspense fallback={<LoadingWorkoutPage />}>
        <WorkoutView dayId={null} />
    </Suspense>
  );
}
