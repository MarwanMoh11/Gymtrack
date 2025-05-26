
// src/app/workout/[day]/page.tsx
// Ensure NO 'use client'; directive is present in this file.
import WorkoutView from '@/components/workout/workout-view';
import { defaultNamedPlans } from '@/data/workout-data'; // For generateStaticParams

type WorkoutPageProps = {
  params: {
    day: string; // This 'day' is the dayId (e.g., 'monday', 'cal-tue')
  };
};

// This page is a Server Component. It passes the dayId to the Client Component.
export default function WorkoutPage({ params }: WorkoutPageProps) {
  return <WorkoutView dayId={params.day} />; // Pass dayId as a prop
}

export async function generateStaticParams() {
  // Generate params for all days in all default plans to ensure they can be prerendered
  // If users can create fully custom day IDs, this might need adjustment or be dynamic.
  const params: { day: string }[] = [];
  defaultNamedPlans.forEach(namedPlan => {
    namedPlan.plan.forEach(day => {
      if (day.id !== 'exercise-library') { // Exclude library pseudo-day
        params.push({ day: day.id });
      }
    });
  });
  return params;
}

