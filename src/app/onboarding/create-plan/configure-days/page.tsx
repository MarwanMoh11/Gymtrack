// src/app/onboarding/create-plan/configure-days/page.tsx
'use client';

import { Suspense } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { useForm, useFieldArray, Controller } from 'react-hook-form';
import { useAuth } from '@/context/auth-context';
import { useMutation, useQueryClient, useQuery } from '@tanstack/react-query';
import { saveUserData, getUserData } from '@/lib/firestore-workout-plan-service';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Loader2, WandSparkles } from 'lucide-react';
import type { WorkoutDay, NamedWorkoutPlan, UserData } from '@/types/workout';
import { useToast } from '@/hooks/use-toast';

const daysOfWeekMap = [
  { name: "Sunday", value: 0 }, { name: "Monday", value: 1 },
  { name: "Tuesday", value: 2 }, { name: "Wednesday", value: 3 },
  { name: "Thursday", value: 4 }, { name: "Friday", value: 5 },
  { name: "Saturday", value: 6 },
];

function ConfigureDaysComponent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const { toast } = useToast();

  const planName = searchParams.get('name') || 'My New Plan';
  const planDescription = searchParams.get('description') || '';
  const daysPerWeek = parseInt(searchParams.get('days') || '1', 10);

  const { control, handleSubmit, watch, formState: { isValid } } = useForm({
    defaultValues: {
      days: Array.from({ length: daysPerWeek }, (_, i) => ({
        dayName: `Day ${i + 1}`,
        title: '',
        mapsToActualDayOfWeek: -1,
      }))
    },
    mode: 'onChange',
  });

  const { fields } = useFieldArray({ control, name: "days" });

  const { data: userData } = useQuery({
    queryKey: ['userData', user?.uid],
    queryFn: () => getUserData(user!.uid),
    enabled: !!user,
  });

  const mutation = useMutation({
    mutationFn: (newUserData: UserData) => saveUserData(user!.uid, newUserData),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['userData', user?.uid] });
      toast({
        title: "Plan Created!",
        description: "Your new plan is active. Now let's add some exercises.",
      });
      router.push('/workout-plan');
    },
    onError: () => {
      toast({ variant: 'destructive', title: 'Error', description: 'Could not create the new plan.' });
    }
  });

  const onSubmit = (data: { days: Partial<WorkoutDay>[] }) => {
    if (!userData) return;

    const newPlanId = `custom-plan-${planName.trim().toLowerCase().replace(/\s+/g, '-')}-${Date.now()}`;
    const newWorkoutDays: WorkoutDay[] = data.days.map((day, index) => ({
      id: `custom-day-${newPlanId}-${index}`,
      dayName: daysOfWeekMap.find(d => d.value === Number(day.mapsToActualDayOfWeek))?.name || `Day ${index + 1}`,
      title: day.title || `Workout Focus ${index + 1}`,
      exercises: [],
      notes: '',
      mapsToActualDayOfWeek: Number(day.mapsToActualDayOfWeek),
    }));

    const newPlan: NamedWorkoutPlan = {
      id: newPlanId,
      name: planName,
      description: planDescription,
      plan: newWorkoutDays,
      isActive: true,
    };

    const updatedOldPlans = userData.plans.map(p => ({ ...p, isActive: false }));
    const newUserData = { ...userData, plans: [...updatedOldPlans, newPlan], onboardingStatus: 'completed' as const };
    
    mutation.mutate(newUserData);
  };
  
  const assignedDays = watch('days').map(d => d.mapsToActualDayOfWeek);

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-background p-4">
      <Card className="w-full max-w-4xl">
        <CardHeader>
          <CardTitle className="text-2xl font-bold text-primary">Build Your Own Plan: Step 2</CardTitle>
          <CardDescription>Now, let's configure your {daysPerWeek} workout day(s). Give each day a focus and assign it to a day of the week.</CardDescription>
        </CardHeader>
        <form onSubmit={handleSubmit(onSubmit)}>
          <CardContent className="space-y-4 max-h-[60vh] overflow-y-auto p-4">
            {fields.map((field, index) => (
              <div key={field.id} className="p-4 border rounded-lg bg-card/50 space-y-3">
                <h3 className="font-semibold text-lg text-secondary-foreground">Workout Day {index + 1}</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <Label htmlFor={`days.${index}.title`}>Focus/Title*</Label>
                    <Controller
                      name={`days.${index}.title`}
                      control={control}
                      rules={{ required: 'Title is required' }}
                      render={({ field, fieldState }) => (
                        <>
                          <Input id={`days.${index}.title`} placeholder="e.g., Upper Body Strength" {...field} />
                          {fieldState.error && <p className="text-sm text-destructive">{fieldState.error.message}</p>}
                        </>
                      )}
                    />
                  </div>
                  <div>
                    <Label htmlFor={`days.${index}.mapsToActualDayOfWeek`}>Day of Week</Label>
                    <Controller
                      name={`days.${index}.mapsToActualDayOfWeek`}
                      control={control}
                      render={({ field }) => (
                         <Select onValueChange={field.onChange} defaultValue={String(field.value)}>
                            <SelectTrigger>
                                <SelectValue placeholder="Assign a day..." />
                            </SelectTrigger>
                            <SelectContent>
                                <SelectItem value="-1">Unassigned</SelectItem>
                                {daysOfWeekMap.filter(d => d.value !== -1).map(dayOption => (
                                    <SelectItem 
                                        key={dayOption.value} 
                                        value={String(dayOption.value)}
                                        disabled={assignedDays.includes(dayOption.value) && Number(field.value) !== dayOption.value}
                                    >
                                        {dayOption.name}
                                    </SelectItem>
                                ))}
                            </SelectContent>
                        </Select>
                      )}
                    />
                  </div>
                </div>
              </div>
            ))}
          </CardContent>
          <CardFooter className="flex justify-end pt-6">
            <Button type="submit" disabled={!isValid || mutation.isPending}>
              {mutation.isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <WandSparkles className="mr-2 h-4 w-4" />}
              Create Plan & Add Exercises
            </Button>
          </CardFooter>
        </form>
      </Card>
    </div>
  );
}

export default function ConfigureDaysPage() {
    return (
        <Suspense fallback={<div>Loading...</div>}>
            <ConfigureDaysComponent />
        </Suspense>
    )
}
