
export enum ExerciseCategory {
    Strength = 'strength',
    Bodyweight = 'bodyweight',
    Cardio = 'cardio',
    Core = 'core',
    Mobility = 'mobility',
    Warmup = 'warmup',
    Plyometrics = 'plyometrics',
    SportSpecific = 'sport_specific',
    Cooldown = 'cooldown',
}

export enum Equipment {
    None = 'None',
    Barbell = 'Barbell',
    Dumbbell = 'Dumbbell',
    Machine = 'Machine',
    Cable = 'Cable',
    Kettlebell = 'Kettlebell',
    Band = 'Band',
    Plate = 'Plate',
    Other = 'Other',
}

export interface GlobalExercise {
    id: string; // "bench-press"
    name: string;
    category: ExerciseCategory | string;
    muscleGroups: string[];
    equipment?: string[]; // Multiple items allowed
    description?: string;
    videoUrl?: string;
    defaultUnit: 'reps' | 's' | 'min';
    difficulty?: 'beginner' | 'intermediate' | 'advanced';
}

export interface SetData {
    id: string;
    targetReps: string; // "8-12", "5", "Failure"
    targetWeight?: string; // "Calculated" or input
    actualReps?: string;
    actualWeight?: string;
    completed?: boolean;
    unit: 'reps' | 's' | 'min';
    exerciseId: string;
}

export interface NewSetData {
    id?: string;
    targetReps: string;
    targetWeight: string;
    unit: 'reps' | 's' | 'min';
}

// PlanExercise is the instance of an exercise within a Workout Plan
// It denormalizes some data for faster read/display
export interface PlanExercise {
    id: string; // Unique instance ID
    globalExerciseId: string; // Reference to GlobalExercise (or custom ID)
    name: string;
    sets: SetData[];

    // Denormalized/Overridable fields
    targetWeight?: string;
    notes?: string;
    description?: string;
    videoUrl?: string;
    muscleGroups?: string[];
    unit: 'reps' | 's' | 'min';

    // Backward compatibility / UI helpers
    category?: ExerciseCategory | string;
    isCompleted?: boolean;
}

// Using 'Exercise' as an alias for PlanExercise for now to minimize refactor friction
export type Exercise = PlanExercise;

export interface WorkoutDay {
    id: string;
    dayName: string; // "Monday", "Push Day"
    title: string;
    notes?: string;
    exercises: PlanExercise[];
    mapsToActualDayOfWeek?: number; // 0=Sun, 1=Mon...
    isRecovery?: boolean;
}

export interface WeeklyPlan extends Array<WorkoutDay> { }

export interface NamedWorkoutPlan {
    id: string;
    name: string;
    description?: string;
    plan: WorkoutDay[];
    isActive: boolean;
}

export interface CustomExercise {
    id: string;
    name: string;
    category: ExerciseCategory | string;
    muscleGroups: string[];
    unit: 'reps' | 's' | 'min';
}

export interface UserData {
    uid: string;
    email: string;
    displayName?: string;
    onboardingStatus: 'new' | 'needs_plan_selection' | 'completed';
    plans: NamedWorkoutPlan[];
    customExercises?: CustomExercise[]; // Private user exercises
    preferences?: {
        theme?: string;
        weightUnit?: 'kg' | 'lbs';
    };
}

// For logging history - matching actual Firestore map structure
export interface LoggedSetData {
    id: string;
    isCompleted: boolean;
    reps?: number;
    weight?: number;
    rpe?: number;
}

// The daily log is stored as a map of ExerciseID -> (Map of SetID -> SetData + name)
export type ExerciseLogData = Record<string, LoggedSetData | string | any> & {
    name?: string;
};

export type DailyLog = Record<string, ExerciseLogData>;
