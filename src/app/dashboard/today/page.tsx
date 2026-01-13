'use client';

import WorkoutView from '@/components/workout/workout-view';
import LoadingWorkoutPage from './loading';
import { Suspense } from 'react';
import { useUser } from '@/context/user-context';
import { useAuth } from '@/context/auth-context';

export default function TodaysWorkoutDashboardPage() {
  const { userData } = useUser();
  const { user } = useAuth();

  const firstName = user?.displayName?.split(' ')[0] || "Athlete";

  return (
    <Suspense fallback={<LoadingWorkoutPage />}>
      <div className="space-y-10 pb-12">
        {/* Header Greeting Section */}
        <div className="flex justify-between items-center animate-in fade-in slide-in-from-bottom-4 duration-700">
          <div>
            <h1 className="text-3xl md:text-4xl font-bold tracking-tight font-heading">
              Rise & <span className="text-primary">Grind</span>
            </h1>
            <p className="text-muted-foreground font-medium mt-1">
              Welcome back, {firstName}
            </p>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center interactive-scale grayscale hover:grayscale-0 transition-all cursor-pointer">
            <div className="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center text-primary font-bold text-xs">
              {firstName[0]}
            </div>
          </div>
        </div>

        {/* Main Content Area - Pass props or keep as is? 
                Actually WorkoutView handles its own data fetching, which is fine, 
                but we can wrap it in a container that matches our new aesthetic.
            */}
        <WorkoutView dayId={null} />

        {/* Weekly Activity / Stats - Could be added here or inside WorkoutView 
                Let's keep it clean for now and focus on making WorkoutView itself look amazing.
            */}
      </div>
    </Suspense>
  );
}
