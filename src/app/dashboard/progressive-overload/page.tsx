// src/app/dashboard/progressive-overload/page.tsx
'use client';
import { useState, useEffect, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import type { DailyLog, WorkoutDay } from '../../../types/workout';
import { History, User, CalendarDays, BarChart } from 'lucide-react';
import LoadingProgressiveOverloadDashboard from './loading';
import { calculateStreaks, getVolumeForMuscleGroups } from '@/lib/workout-utils';
import { getUserData } from '@/lib/firestore-workout-plan-service';
import { getAllUserLogs } from '@/lib/firestore-log-service';
import { useToast } from '@/hooks/use-toast';
import { Card, CardHeader, CardTitle, CardContent, CardDescription } from '@/components/ui/card';
import CalendarWidget from '@/components/dashboard/calendar-widget';
import MuscleHeatmap from '@/components/dashboard/muscle-heatmap';
import MuscleDetailView from '@/components/dashboard/muscle-detail-view';

const getPastWeekDates = (): string[] => {
  const dates: string[] = [];
  for (let i = 0; i < 7; i++) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    dates.push(d.toISOString().split('T')[0]);
  }
  return dates;
};

export default function ProgressiveOverloadDashboardPage() {
  const { user } = useAuth();
  const [isClient, setIsClient] = useState(false);
  const [selectedMuscle, setSelectedMuscle] = useState<string | null>(null);

  const { data: userData, isLoading: isLoadingUserData } = useQuery({
    queryKey: ['userData', user?.uid],
    queryFn: () => getUserData(user!.uid),
    enabled: !!user,
  });

  const { data: allLogs, isLoading: isLoadingLogs } = useQuery({
    queryKey: ['allUserLogs', user?.uid],
    queryFn: () => getAllUserLogs(user!.uid),
    enabled: !!user,
  });

  useEffect(() => {
    setIsClient(true);
  }, []);

  const { loggedDays, streaks } = useMemo(() => {
    if (!allLogs) return { loggedDays: [], streaks: { current: 0, longest: 0 } };
    const dates = Array.from(allLogs.keys()).map(dateStr => {
      const [year, month, day] = dateStr.split('-').map(Number);
      return new Date(Date.UTC(year, month - 1, day));
    });
    const calculatedStreaks = calculateStreaks(dates);
    return { loggedDays: dates, streaks: calculatedStreaks };
  }, [allLogs]);

  const muscleVolumes = useMemo(() => {
    if (!allLogs || !userData) return {};
    const weekDates = getPastWeekDates();
    return getVolumeForMuscleGroups(weekDates, allLogs, userData.plans);
  }, [allLogs, userData]);

  const handleMuscleClick = (muscle: string) => {
    setSelectedMuscle(prev => prev === muscle ? null : muscle);
  };

  const activePlan = useMemo(() => userData?.plans.find(p => p.isActive), [userData]);

  if (!isClient || isLoadingUserData || isLoadingLogs) {
    return <LoadingProgressiveOverloadDashboard />;
  }

  return (
    <div className="container mx-auto py-8 px-4 md:px-6 space-y-10">
      <div className="flex flex-col sm:flex-row justify-between items-center gap-4">
        <h1 className="text-3xl font-bold text-primary flex items-center">
          <History className="mr-3 h-8 w-8" />
          Progress Dashboard
        </h1>
      </div>

      {/* Primary Focus: Calendar Widget (Training Consistency) */}
      <div className="animate-in fade-in slide-in-from-top-4 duration-700">
        <CalendarWidget
          loggedDays={loggedDays}
          streaks={streaks}
          allLogs={allLogs!}
          activePlan={activePlan}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-1 gap-8 items-start">
        {/* Analytics Section: Muscle Heatmap and Details */}
        <div className="space-y-10">
          <Card className="shadow-lg rounded-[2.5rem] overflow-hidden border-white/5 animate-in fade-in slide-in-from-bottom-4 duration-700">
            <CardHeader className="pb-2">
              <div className="flex items-center gap-3">
                <User className="h-6 w-6 text-primary/80" />
                <CardTitle className="text-2xl font-bold">Biometric Load Heatmap</CardTitle>
              </div>
              <CardDescription className="text-muted-foreground/60 font-medium">
                Volume density analysis for the last 7 days. Focus on latent potential areas.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <MuscleHeatmap
                muscleVolumes={muscleVolumes}
                onMuscleClick={handleMuscleClick}
                selectedMuscle={selectedMuscle}
              />
            </CardContent>
          </Card>

          {selectedMuscle && (
            <MuscleDetailView
              muscle={selectedMuscle}
              volume={muscleVolumes[selectedMuscle] || 0}
              allLogs={allLogs!}
              activePlan={activePlan!}
            />
          )}

        </div>
      </div>
    </div>
  );
}
