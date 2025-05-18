
'use client';

import type { SetData, LoggedSetData } from '@/types/workout';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Check, Edit3, Plus, Minus, History, Sparkles } from 'lucide-react'; // Added History, Sparkles
import { useState, useEffect } from 'react';
import { cn } from '@/lib/utils';

interface SetLoggerProps {
  setNumber: number;
  setData: SetData; // Includes target reps/weight for the set definition
  loggedSetData?: LoggedSetData; // Data logged specifically for this set instance
  lastSessionSetPerformance?: LoggedSetData; // Performance for THIS set from the LAST session
  effectiveTargetWeight?: string; // The weight planned for this exercise today
  onLogSet: (log: LoggedSetData) => void;
  exerciseUnit?: 'reps' | 's' | 'min';
  isSimpleLog?: boolean; // For exercises like conditioning, warmups etc.
  isEditingInitially?: boolean; // Control initial edit state
}

export default function SetLogger({
  setNumber,
  setData,
  loggedSetData,
  lastSessionSetPerformance,
  effectiveTargetWeight,
  onLogSet,
  exerciseUnit,
  isSimpleLog = false,
  isEditingInitially = !loggedSetData?.isCompleted,
}: SetLoggerProps) {
  const unitLabel = setData.unit || exerciseUnit || 'reps';

  const getInitialReps = () => {
    if (loggedSetData?.reps !== undefined) return String(loggedSetData.reps);
    // If starting edit and no current log, suggest based on last session's performance + 1 (if numeric)
    if (isEditingInitially && lastSessionSetPerformance?.reps !== undefined) {
        const lastRepsNum = parseInt(String(lastSessionSetPerformance.reps), 10);
        if (!isNaN(lastRepsNum)) {
            // return String(lastRepsNum + 1); // Suggesting increase
            return String(lastRepsNum); // Or just show what they did last time
        }
        return String(lastSessionSetPerformance.reps); // If not numeric, just show as is
    }
    return ''; // Default to empty
  };

  const [currentReps, setCurrentReps] = useState<string>(getInitialReps);
  const [isEditing, setIsEditing] = useState(isEditingInitially);

  useEffect(() => {
    setIsEditing(isEditingInitially);
    if (isEditingInitially) {
        if (loggedSetData?.reps !== undefined) {
           setCurrentReps(String(loggedSetData.reps));
        } else if (lastSessionSetPerformance?.reps !== undefined) {
            // Use last session's actual reps if available when starting fresh edit
           setCurrentReps(String(lastSessionSetPerformance.reps));
        } else {
           setCurrentReps(''); // Fallback to empty
        }
    }
   }, [isEditingInitially, loggedSetData?.reps, lastSessionSetPerformance?.reps]);

   useEffect(() => {
    if (!loggedSetData && isEditing) {
       setCurrentReps(lastSessionSetPerformance?.reps !== undefined ? String(lastSessionSetPerformance.reps) : '');
    }
   }, [loggedSetData, isEditing, lastSessionSetPerformance?.reps]);


  const handleLog = () => {
    const repsToLog = currentReps || 
                      (lastSessionSetPerformance?.reps !== undefined ? String(lastSessionSetPerformance.reps) : setData.targetReps);
    onLogSet({
      reps: repsToLog,
      weight: effectiveTargetWeight || setData.targetWeight, 
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
        reps: setData.targetReps, 
        weight: effectiveTargetWeight || setData.targetWeight,
        isCompleted: true
    });
     setIsEditing(false);
  }

  const handleMarkAsNotDone = () => {
    onLogSet({ reps: loggedSetData?.reps, weight: loggedSetData?.weight, isCompleted: false });
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
        if (!isNaN(lastRepsNum)) {
            return String(lastRepsNum + 1); // Suggest one more rep than last time
        }
        return String(lastSessionSetPerformance.reps); // If not numeric, show as is
    }
    return String(setData.targetReps); // Fallback to plan's target
  };
  
  // Gamification: Check if current performance beats last session
  const performanceBeatLast = useMemo(() => {
    if (!loggedSetData?.isCompleted || !lastSessionSetPerformance?.isCompleted) return null;

    const currentRepsNum = parseInt(String(loggedSetData.reps), 10);
    const lastRepsNum = parseInt(String(lastSessionSetPerformance.reps), 10);
    // Assuming weight is consistent for this comparison, or add weight comparison too
    if (!isNaN(currentRepsNum) && !isNaN(lastRepsNum) && currentRepsNum > lastRepsNum) {
        return { type: 'reps', diff: currentRepsNum - lastRepsNum };
    }
    // Could extend to weight PRs too
    return null;
  }, [loggedSetData, lastSessionSetPerformance]);


  if (isSimpleLog) {
    return (
      <div className="flex items-center justify-between p-3 border-t border-border/50">
        <div className="flex items-center gap-2">
          <span className="font-medium text-sm w-12">Set {setNumber}:</span>
          <span className="text-sm text-muted-foreground">{setData.targetReps} {setData.targetWeight ? `(${setData.targetWeight})` : ''}</span>
        </div>
        {loggedSetData?.isCompleted ? (
           <Button variant="ghost" size="sm" onClick={handleMarkAsNotDone} className="text-muted-foreground hover:text-foreground">
             <Check className="mr-1 h-4 w-4 text-primary" /> Done
           </Button>
        ) : (
          <Button variant="outline" size="sm" onClick={handleMarkAsDone}>
            Mark as Done
          </Button>
        )}
      </div>
    );
  }

  if (!isEditing && loggedSetData?.isCompleted) {
    return (
      <div className={cn(
        "flex items-center justify-between p-3 border-t border-border/50",
        performanceBeatLast ? "bg-primary/10" : "bg-secondary/30" // Highlight if PR
      )}>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
          <span className="font-medium w-12">Set {setNumber}:</span>
          <span>Target: {setData.targetReps} {unitLabel}</span>
          <span className={cn(
            "font-semibold flex items-center",
            performanceBeatLast ? "text-primary" : "text-foreground"
          )}>
            Logged: {loggedSetData.reps ?? 'N/A'} {unitLabel}
            {performanceBeatLast && performanceBeatLast.type === 'reps' && (
              <span className="ml-1.5 text-xs flex items-center text-green-500">(<Sparkles className="h-3 w-3 mr-0.5" /> +{performanceBeatLast.diff}!)</span>
            )}
          </span>
          {lastSessionSetPerformance && (
            <span className="text-xs text-muted-foreground/80 flex items-center">
              <History className="h-3 w-3 mr-1 opacity-70" />
              Last: {lastSessionSetPerformance.reps} {unitLabel}
              {lastSessionSetPerformance.weight && ` @ ${lastSessionSetPerformance.weight}`}
            </span>
          )}
        </div>
        <Button variant="ghost" size="icon" onClick={handleEdit} className="h-8 w-8">
          <Edit3 className="h-4 w-4" />
        </Button>
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
             <Button onClick={decrementReps} size="icon" variant="outline" className="h-9 w-9 shrink-0">
              <Minus className="h-4 w-4" />
              <span className="sr-only">Decrement reps</span>
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
            />
             <Button onClick={incrementReps} size="icon" variant="outline" className="h-9 w-9 shrink-0">
              <Plus className="h-4 w-4" />
              <span className="sr-only">Increment reps</span>
            </Button>
          </div>
        </div>
        <Button onClick={handleLog} size="sm" className="h-9 shrink-0 self-end">
          <Check className="h-4 w-4" />
          <span className="sr-only sm:not-sr-only sm:ml-1">Log</span>
        </Button>
      </div>
      {lastSessionSetPerformance && (
        <div className="pl-[calc(3rem+0.5rem)] text-xs text-muted-foreground/70 flex items-center"> {/* Align with input field */}
            <History className="h-3 w-3 mr-1 opacity-60" />
            Last time: {lastSessionSetPerformance.reps} {unitLabel}
            {lastSessionSetPerformance.weight && ` @ ${lastSessionSetPerformance.weight}`}
        </div>
      )}
    </div>
  );
}

