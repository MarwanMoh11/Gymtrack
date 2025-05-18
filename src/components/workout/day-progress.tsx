
'use client';

import { Progress } from '@/components/ui/progress';

interface DayProgressProps {
  completedSets: number;
  totalSets: number;
}

export default function DayProgress({ completedSets, totalSets }: DayProgressProps) {
  const progressPercentage = totalSets > 0 ? Math.round((completedSets / totalSets) * 100) : 0;

  if (totalSets === 0) {
    return null; // No sets to track
  }

  return (
    <div className="w-full">
      <div className="mb-1 flex justify-between text-xs font-medium text-muted-foreground">
        <span>Overall Progress</span>
        <span>{progressPercentage}%</span>
      </div>
      <Progress value={progressPercentage} aria-label={`Workout progress: ${progressPercentage}%`} className="h-3" />
    </div>
  );
}
