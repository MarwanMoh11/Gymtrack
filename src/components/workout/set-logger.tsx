
'use client';

import type { LoggedSetData, SetData, DailyLog, NamedWorkoutPlan } from '@/types/workout';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Check, Edit3, Plus, Minus, History, Sparkles, ChevronRight } from 'lucide-react';
import { useState, useEffect, useMemo } from 'react';
import { cn } from '@/lib/utils';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getAllUserLogs, getDailyLog } from '@/lib/firestore-log-service';
import { useAuth } from '@/context/auth-context';
import { getPreviousSetPerformance } from '@/lib/workout-utils';

interface SetLoggerProps {
  setNumber: number;
  setData: SetData;
  loggedSetData?: LoggedSetData;
  effectiveTargetWeight?: string;
  onLogSet: (logData: { reps: string; isCompleted: boolean; }) => void;
  exerciseUnit?: 'reps' | 's' | 'min';
  isSimpleLog?: boolean;
  isEditingInitially?: boolean;
  activePlan?: NamedWorkoutPlan;
}

const getCurrentDateString = (): string => {
  return new Date().toISOString().split('T')[0];
};


export default function SetLogger({
  setNumber,
  setData,
  loggedSetData,
  effectiveTargetWeight,
  onLogSet,
  exerciseUnit,
  isSimpleLog = false,
  isEditingInitially = !loggedSetData?.isCompleted,
  activePlan,
}: SetLoggerProps) {
  const { user } = useAuth();
  const unitLabel = setData.unit || exerciseUnit || 'reps';
  const currentDate = getCurrentDateString();

  const { data: allLogs } = useQuery({
    queryKey: ['allUserLogs', user?.uid],
    queryFn: () => getAllUserLogs(user!.uid),
    enabled: !!user,
  });

  const { data: todayLog } = useQuery<DailyLog | null>({
    queryKey: ['dailyLog', user?.uid, currentDate],
    queryFn: () => getDailyLog(user!.uid, currentDate),
    enabled: !!user,
  });

  const lastSessionSetPerformance = useMemo(() => {
    if (!allLogs || !activePlan) return undefined;
    return getPreviousSetPerformance(setData.exerciseId, setData.id, allLogs, activePlan, todayLog ?? undefined);
  }, [allLogs, todayLog, setData.exerciseId, setData.id, activePlan]);

  const getInitialReps = () => {
    if (loggedSetData?.reps !== undefined && loggedSetData.reps !== null && String(loggedSetData.reps).trim() !== '') return String(loggedSetData.reps);
    if (lastSessionSetPerformance?.reps !== undefined) return String(lastSessionSetPerformance.reps);
    return '';
  };

  const [currentReps, setCurrentReps] = useState<string>(getInitialReps);
  const [isEditing, setIsEditing] = useState(isEditingInitially);

  useEffect(() => {
    setIsEditing(isEditingInitially);
    if (isEditingInitially) {
      setCurrentReps(getInitialReps());
    }
  }, [isEditingInitially, loggedSetData, lastSessionSetPerformance]);


  const handleLog = () => {
    const repsToLog = String(currentReps).trim() !== ''
      ? currentReps
      : (lastSessionSetPerformance?.reps !== undefined ? String(lastSessionSetPerformance.reps) : String(setData.targetReps));

    onLogSet({
      reps: repsToLog,
      isCompleted: true
    });
    setIsEditing(false);
  };

  const handleEdit = () => {
    setIsEditing(true);
    setCurrentReps(loggedSetData?.reps !== undefined ? String(loggedSetData.reps) : '');
  }

  const handleMarkAsDone = () => {
    onLogSet({
      reps: String(setData.targetReps),
      isCompleted: true
    });
    setIsEditing(false);
  }

  const handleMarkAsNotDone = () => {
    onLogSet({ reps: String(loggedSetData?.reps || ''), isCompleted: false });
    setIsEditing(true);
    setCurrentReps(loggedSetData?.reps !== undefined ? String(loggedSetData.reps) : '');
  }


  const incrementReps = () => {
    setCurrentReps(prev => String(Number(prev || 0) + 1));
  };

  const decrementReps = () => {
    setCurrentReps(prev => String(Math.max(0, Number(prev || 0) - 1)));
  };

  const getPlaceholderReps = () => {
    if (lastSessionSetPerformance?.reps !== undefined) {
      const lastRepsNum = parseInt(String(lastSessionSetPerformance.reps), 10);
      if (!isNaN(lastRepsNum) && unitLabel === 'reps') {
        return String(lastRepsNum + 1);
      }
      return String(lastSessionSetPerformance.reps);
    }
    return String(setData.targetReps);
  };

  const performanceBeatLast = useMemo(() => {
    if (!loggedSetData?.isCompleted || !lastSessionSetPerformance?.isCompleted) return null;

    const currentRepsNum = parseInt(String(loggedSetData.reps), 10);
    const lastRepsNum = parseInt(String(lastSessionSetPerformance.reps), 10);

    if (isNaN(currentRepsNum) || isNaN(lastRepsNum)) return null;

    if (currentRepsNum > lastRepsNum) {
      return { type: 'reps', diff: currentRepsNum - lastRepsNum, message: `BEAT LAST LOG (+${currentRepsNum - lastRepsNum})` };
    }
    if (currentRepsNum === lastRepsNum) {
      return { type: 'maintained', message: `EQUALED PREVIOUS` };
    }
    if (currentRepsNum < lastRepsNum) {
      return { type: 'decreased', message: `BELOW PREVIOUS` };
    }

    return null;
  }, [loggedSetData, lastSessionSetPerformance]);


  if (isSimpleLog) {
    const isCompleted = loggedSetData?.isCompleted ?? false;
    return (
      <div className="flex items-center justify-between py-6 px-1 border-b border-white/5">
        <div className="flex items-center gap-4">
          <div className="w-10 h-10 rounded-xl bg-white/5 flex items-center justify-center font-bold text-xs opacity-40">
            {setNumber}
          </div>
          <span className="text-sm font-semibold tracking-tight">{setData.targetReps} {unitLabel} Protocol</span>
        </div>
        <Button
          variant={isCompleted ? "secondary" : "default"}
          onClick={isCompleted ? handleMarkAsNotDone : handleMarkAsDone}
          className={cn(
            "h-12 px-6 rounded-xl font-bold uppercase tracking-widest text-[10px] interactive-scale",
            isCompleted ? "bg-primary/20 text-primary border-primary/20" : "bg-primary text-background shadow-lg shadow-primary/20"
          )}
        >
          {isCompleted ? "Protocol Secured" : "Log Victory"}
        </Button>
      </div>
    );
  }

  if (!isEditing && loggedSetData?.isCompleted) {
    const isPR = performanceBeatLast?.type === 'reps';

    return (
      <div className={cn(
        "py-6 px-6 rounded-[1.5rem] transition-all duration-500 border-none group relative overflow-hidden my-2",
        isPR ? "bg-primary shadow-xl shadow-primary/30" : "bg-white/5"
      )}>
        <div className="flex justify-between items-center relative z-10">
          <div className="flex items-center gap-6">
            <div className={cn(
              "w-12 h-12 rounded-2xl flex items-center justify-center font-black text-sm",
              isPR ? "bg-background text-primary" : "bg-white/10 text-foreground/50"
            )}>
              {setNumber}
            </div>
            <div>
              <div className="flex items-center gap-3">
                <p className={cn(
                  "text-xl font-black tracking-tighter uppercase",
                  isPR ? "text-background" : "text-foreground"
                )}>
                  {loggedSetData.reps ?? '0'} {unitLabel}
                </p>
                {isPR && (
                  <div className="flex items-center gap-1 bg-background/20 px-2 py-0.5 rounded-full backdrop-blur-md">
                    <Sparkles className="h-3 w-3 text-background" />
                    <span className="text-[9px] font-black text-background">NEW PR</span>
                  </div>
                )}
              </div>
              {performanceBeatLast && (
                <p className={cn(
                  "text-[10px] font-bold uppercase tracking-[0.2em] mt-0.5",
                  isPR ? "text-background/60" : "text-muted-foreground/60"
                )}>
                  {performanceBeatLast.message}
                </p>
              )}
            </div>
          </div>
          <Button
            variant="secondary"
            size="icon"
            onClick={handleEdit}
            className={cn(
              "h-10 w-10 rounded-xl interactive-scale",
              isPR ? "bg-background/20 hover:bg-background/30 text-background border-none" : "bg-white/5"
            )}
          >
            <Edit3 className="h-4 w-4" />
          </Button>
        </div>

        {isPR && (
          <div className="absolute top-0 right-0 w-32 h-32 bg-white/20 rounded-full -mr-16 -mt-16 blur-2xl opacity-50" />
        )}
      </div>
    );
  }

  return (
    <div className="py-8 px-1 border-b border-white/5">
      <div className="flex items-center gap-6">
        <div className="hidden sm:flex w-14 h-14 rounded-2xl bg-white/5 border border-white/10 items-center justify-center font-black text-sm text-foreground/30">
          {setNumber}
        </div>

        <div className="flex-1 space-y-4">
          <div className="flex justify-between items-end">
            <div className="flex items-baseline gap-1.5">
              <span className="text-xs font-bold uppercase tracking-widest text-primary">Target:</span>
              <span className="text-xl font-black tracking-tight">{setData.targetReps} {unitLabel}</span>
            </div>
            {lastSessionSetPerformance && (
              <div className="flex items-center gap-1.5 opacity-40">
                <History className="h-3 w-3" />
                <span className="text-[10px] font-bold uppercase tracking-widest">Last: {lastSessionSetPerformance.reps}</span>
              </div>
            )}
          </div>

          <div className="grid grid-cols-[1fr,auto,1fr] items-center gap-4 max-w-[280px]">
            <Button onClick={decrementReps} variant="outline" className="h-14 rounded-2xl border-white/10 hover:bg-white/5 interactive-scale">
              <Minus className="h-6 w-6" />
            </Button>

            <div className="text-center group">
              <Input
                type="number"
                inputMode="numeric"
                placeholder={getPlaceholderReps()}
                value={currentReps}
                onChange={(e) => setCurrentReps(e.target.value.replace(/[^0-9]/g, ''))}
                className="h-14 border-none bg-transparent text-3xl font-black text-center w-20 p-0 focus-visible:ring-0 focus-visible:ring-offset-0"
              />
              <div className="h-[2px] w-full bg-primary/20 group-focus-within:bg-primary transition-colors" />
              <p className="text-[9px] font-bold uppercase tracking-widest mt-1 opacity-30">{unitLabel}</p>
            </div>

            <Button onClick={incrementReps} variant="outline" className="h-14 rounded-2xl border-primary/20 text-primary hover:bg-primary/5 interactive-scale">
              <Plus className="h-6 w-6" />
            </Button>
          </div>
        </div>

        <Button
          onClick={handleLog}
          className="h-14 w-14 sm:w-28 rounded-2xl bg-primary text-background shadow-xl shadow-primary/20 interactive-scale shrink-0"
        >
          <Check className="h-6 w-6 sm:h-5 sm:w-5" />
          <span className="hidden sm:inline-block ml-2 font-black uppercase text-[10px] tracking-widest">Log</span>
        </Button>
      </div>
    </div>
  );
}
