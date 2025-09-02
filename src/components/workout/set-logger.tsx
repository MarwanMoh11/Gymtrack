
'use client';

import type { LoggedSetData, SetData, DailyLog } from '@/types/workout';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Check, Edit3, Plus, Minus, History, Sparkles } from 'lucide-react';
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
}: SetLoggerProps) {
  const { user } = useAuth();
  const unitLabel = setData.unit || exerciseUnit || 'reps';
  const currentDate = getCurrentDateString();

  const { data: allLogs, isLoading: isLoadingLogs } = useQuery({
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
    if (!allLogs) return undefined;
    return getPreviousSetPerformance(setData.exerciseId, setData.id, allLogs, todayLog ?? undefined);
  }, [allLogs, todayLog, setData.exerciseId, setData.id]);

  const getInitialReps = () => {
    if (loggedSetData?.reps !== undefined && loggedSetData.reps !== null && String(loggedSetData.reps).trim() !== '') return String(loggedSetData.reps);
    // Pre-fill with last session's reps if available
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
    // If the input is empty, default to the placeholder (which is last session's reps or target reps)
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
    // When un-completing, we keep the reps data but mark as incomplete.
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
            // Suggest an increase if possible for reps-based exercises
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
    
    // For now, any increase is a PR. More complex logic could be added for weight+reps.
    if (currentRepsNum > lastRepsNum) {
        return { type: 'reps', diff: currentRepsNum - lastRepsNum, message: `+${currentRepsNum - lastRepsNum} Reps! Great Progress!` };
    }
    if (currentRepsNum === lastRepsNum) {
        return { type: 'maintained', message: `Maintained, stay consistent.` };
    }
    if (currentRepsNum < lastRepsNum) {
        return { type: 'decreased', message: `Slight drop, aim higher next time.` };
    }
    
    return null;
  }, [loggedSetData, lastSessionSetPerformance]);


  if (isSimpleLog) {
    const isCompleted = loggedSetData?.isCompleted ?? false;
    return (
      <div className="flex items-center justify-between p-3 border-t border-border/50">
        <div className="flex items-center gap-2">
          <span className="font-medium text-sm w-12 shrink-0">Set {setNumber}:</span>
          <span className="text-sm text-muted-foreground">{setData.targetReps} {setData.unit ? `(${setData.unit})` : ''}</span>
        </div>
        <Button 
          variant={isCompleted ? "secondary" : "default"} 
          size="sm" 
          onClick={isCompleted ? handleMarkAsNotDone : handleMarkAsDone}
          className="w-28"
        >
          {isCompleted && <Check className="mr-1 h-4 w-4 text-primary" />}
          {isCompleted ? "Completed" : "Mark Done"}
        </Button>
      </div>
    );
  }

  if (!isEditing && loggedSetData?.isCompleted) {
    const isPR = performanceBeatLast?.type === 'reps';
    
    return (
      <div className={cn(
        "p-3 border-t border-border/50",
        isPR ? "bg-primary/10 border-l-4 border-l-primary" : "bg-secondary/30"
      )}>
        <div className="flex justify-between items-center">
            <div className="flex flex-col sm:flex-row sm:items-center sm:gap-x-4 gap-y-1 text-sm">
              <span className="font-medium w-12">Set {setNumber}:</span>
              <span className={cn(
                "font-semibold flex items-center",
                isPR ? "text-primary" : "text-foreground"
              )}>
                Logged: {loggedSetData.reps ?? 'N/A'} {unitLabel}
              </span>
              {lastSessionSetPerformance && (
                <span className="text-xs text-muted-foreground/80 flex items-center">
                  <History className="h-3 w-3 mr-1 opacity-70" />
                  Last time: {lastSessionSetPerformance.reps} {unitLabel}
                </span>
              )}
            </div>
             <Button variant="ghost" size="icon" onClick={handleEdit} className="h-8 w-8">
              <Edit3 className="h-4 w-4" />
            </Button>
        </div>
        {performanceBeatLast && (
           <div className={cn(
               "text-xs mt-1 pl-[calc(3rem)] flex items-center",
                isPR ? "text-green-500 font-semibold" : "text-muted-foreground",
                performanceBeatLast?.type === 'decreased' && "text-amber-500"
            )}>
              {isPR && <Sparkles className="h-3 w-3 mr-1" />}
              {performanceBeatLast.message}
            </div>
        )}
      </div>
    );
  }

  return (
    <div className="p-3 border-t border-border/50">
      <div className="flex items-end gap-2 sm:gap-3 mb-1.5">
        <Label htmlFor={`set-${setNumber}-reps`} className="w-12 pt-1 text-sm font-medium shrink-0">
          Set {setNumber}
        </Label>
        <div className="flex-1">
          <Label htmlFor={`set-${setNumber}-reps`} className="text-xs text-muted-foreground">
            {unitLabel.charAt(0).toUpperCase() + unitLabel.slice(1)} (Plan: {setData.targetReps})
          </Label>
          <div className="flex items-center gap-1 mt-1">
             <Button onClick={decrementReps} size="icon" variant="outline" className="h-9 w-9 shrink-0" aria-label="Decrement reps">
              <Minus className="h-4 w-4" />
            </Button>
            <Input
              id={`set-${setNumber}-reps`}
              type="number"
              inputMode="numeric"
              pattern="[0-9]*"
              placeholder={getPlaceholderReps()}
              value={currentReps}
              onChange={(e) => setCurrentReps(e.target.value.replace(/[^0-9]/g, ''))}
              className="h-9 text-lg font-semibold text-center appearance-none w-16 flex-shrink-0"
              style={{ MozAppearance: 'textfield' }} 
              aria-label={`Reps for set ${setNumber}`}
            />
             <Button onClick={incrementReps} size="icon" variant="outline" className="h-9 w-9 shrink-0" aria-label="Increment reps">
              <Plus className="h-4 w-4" />
            </Button>
          </div>
        </div>
        <Button onClick={handleLog} size="sm" className="h-9 shrink-0 self-end">
          <Check className="h-4 w-4" />
          <span className="sr-only sm:not-sr-only sm:ml-1">Log</span>
        </Button>
      </div>
      {lastSessionSetPerformance && (
        <div className="pl-[calc(3rem+0.5rem)] text-xs text-muted-foreground/70 flex items-center">
            <History className="h-3 w-3 mr-1 opacity-60" />
            Last time: {lastSessionSetPerformance.reps} {unitLabel}
            {lastSessionSetPerformance.weight && ` @ ${lastSessionSetPerformance.weight}`}
        </div>
      )}
    </div>
  );
}
