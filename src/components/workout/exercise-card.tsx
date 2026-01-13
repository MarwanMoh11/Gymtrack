
// src/components/workout/exercise-card.tsx
// This component is now DEPRECATED for the main workout logging flow.
// Its functionality for displaying exercise details and logging sets has been moved
// to the new /exercises/[exerciseId]/page.tsx.
// This file can be kept for reference or if specific parts are reused elsewhere,
// but it's no longer central to the /dashboard/today workout experience.

'use client';

import Link from 'next/link';
import { Card, CardHeader, CardTitle, CardContent, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Info, XSquare, Undo2, Lock, Edit, Save, XCircle, ArrowUpCircle } from 'lucide-react';
import type { Exercise, ExerciseLogData as LoggedExerciseData, SetData, LoggedSetData } from '../../types/workout';
// SetLogger and AIRecommendationModal are no longer used directly here if logging moves.
// import SetLogger from './set-logger';
// import AIRecommendationModal from './ai-recommendation-modal';
// import { getPreviousSetPerformance } from '@/lib/workout-utils';
// import { Input } from '@/components/ui/input';
// import { Label } from '@/components/ui/label';
import {
  AlertDialog,
  // AlertDialogAction,
  // AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog"
import { cn } from '@/lib/utils';


interface ExerciseCardProps {
  exercise: Exercise;
  // These props relate to inline logging, which is moving:
  // effectiveTargetWeight?: string;
  // onLogSet: (exerciseId: string, setId: string, log: LoggedSetData) => void;
  // loggedData?: LoggedExerciseData;
  // onUpdateEffectiveTargetWeight: (exerciseId: string, newWeight: string) => void;
  // triggerRepReset: (exerciseId: string) => void;
  onSkipExercise?: (exerciseId: string) => void; // May still be useful for a quick skip on summary
  onUnskipExercise?: (exerciseId: string) => void; // May still be useful
  isSkipped?: boolean;
  dayId?: string; // To construct link to detail page correctly
}

export default function ExerciseCard({
  exercise,
  onSkipExercise,
  onUnskipExercise,
  isSkipped,
  dayId,
}: ExerciseCardProps) {
  // const [isAIRecModalOpen, setIsAIRecModalOpen] = useState(false);
  // const [isEditingTarget, setIsEditingTarget] = useState(false);
  // const [manualTargetWeight, setManualTargetWeight] = useState(effectiveTargetWeight || exercise.targetWeight || '');
  // const [forceSetEditKey, setForceSetEditKey] = useState(0);
  // const [canSuggestWeightIncrease, setCanSuggestWeightIncrease] = useState(false);

  // All logging logic, target weight editing, AI modal triggering is moved to
  // /src/app/exercises/[exerciseId]/page.tsx

  const isSpecialActivity = ['cardio', 'mobility', 'warmup', 'cooldown'].includes(exercise.category as string);
  const canShowSkipButton = exercise.sets.length > 0 && onSkipExercise && onUnskipExercise;

  const renderSkipUnskipButton = () => {
    if (!canShowSkipButton) return null;

    if (isSkipped) {
      return (
        <Button
          variant="ghost"
          size="icon"
          onClick={() => onUnskipExercise && onUnskipExercise(exercise.id)}
          className="h-7 w-7 text-muted-foreground hover:text-primary shrink-0"
          aria-label={`Unskip ${exercise.name}`}
        >
          <Undo2 className="h-4 w-4" />
          <span className="sr-only">Unskip {exercise.name}</span>
        </Button>
      );
    } else {
      return (
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button
              variant="ghost"
              size="icon"
              className="h-7 w-7 text-muted-foreground hover:text-destructive shrink-0"
              aria-label={`Skip ${exercise.name}`}
            >
              <XSquare className="h-4 w-4" />
              <span className="sr-only">Skip ${exercise.name}</span>
            </Button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Skip Exercise: {exercise.name}?</AlertDialogTitle>
              <AlertDialogDescription>
                This will mark all sets for "{exercise.name}" as not completed for today.
                You can log sets for this exercise later by going to its detail page.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              {/* <AlertDialogCancel>Cancel</AlertDialogCancel>
               <AlertDialogAction onClick={() => onSkipExercise && onSkipExercise(exercise.id)} className="bg-destructive hover:bg-destructive/90 text-destructive-foreground">
                Skip Exercise
               </AlertDialogAction> */}
              {/* Simplified for now, real actions would be passed or handled by parent */}
              <Button variant="outline" onClick={() => {/* Close dialog */ }}>Cancel</Button>
              <Button onClick={() => onSkipExercise && onSkipExercise(exercise.id)} className="bg-destructive hover:bg-destructive/90 text-destructive-foreground">
                Skip Exercise
              </Button>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      );
    }
  };

  const linkHref = dayId ? `/exercises/${exercise.id}?dayId=${dayId}` : `/exercises/${exercise.id}`;

  return (
    <Card className={cn(
      "mb-6 shadow-md hover:shadow-lg transition-shadow duration-300 relative",
      isSkipped && "bg-card/50 opacity-70"
    )}>
      <CardHeader className="pb-2">
        <div className="flex justify-between items-start">
          <div className="flex items-center gap-2">
            <Link href={linkHref} passHref legacyBehavior>
              <a className="hover:underline focus:outline-none focus:ring-1 focus:ring-primary rounded">
                <CardTitle className="text-xl font-semibold text-foreground hover:text-primary transition-colors">
                  {exercise.name}
                </CardTitle>
              </a>
            </Link>
            <Link href={`/exercises/${exercise.id}${dayId ? `?dayId=${dayId}` : ''}`} passHref legacyBehavior>
              <a aria-label={`More information about ${exercise.name}`} className="text-muted-foreground hover:text-primary transition-colors">
                <Info className="h-4 w-4" />
              </a>
            </Link>
          </div>

          <div className="flex items-center gap-2">
            {isSkipped && (
              <Badge variant="destructive" className="text-xs font-normal">
                <Lock className="h-3 w-3 mr-1" /> Skipped
              </Badge>
            )}
            {exercise.notes && !isSkipped && (
              <Badge variant="secondary" className="whitespace-nowrap ml-2 shrink-0 text-xs">{exercise.notes}</Badge>
            )}
            {/* {renderSkipUnskipButton()} */} {/* Quick skip might be re-added to summary view later */}
          </div>
        </div>
        {exercise.targetWeight && (
          <CardDescription className="text-xs text-muted-foreground/70 mt-1">
            Base Plan: {exercise.targetWeight}
          </CardDescription>
        )}
        {/* Target weight controls moved to exercise detail page */}
      </CardHeader>
      <CardContent className={cn("p-3 pt-1", isSkipped && "opacity-40 pointer-events-none")}>
        {/* Set logging UI moved to exercise detail page */}
        <p className="text-sm text-muted-foreground">
          {exercise.sets.length} sets planned. Target: {exercise.sets.map((s: SetData) => s.targetReps).join(' / ')} {exercise.unit || 'reps'}.
        </p>
        <p className="text-xs text-muted-foreground mt-1">
          Tap to log sets and view details.
        </p>
      </CardContent>
      {/* AI Button moved to exercise detail page */}
    </Card>
  );
}
