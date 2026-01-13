// src/app/onboarding/create-plan/configure-days/page.tsx
'use client';

import { Suspense } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { useForm, useFieldArray, Controller } from 'react-hook-form';
import type { WorkoutDay, NamedWorkoutPlan, UserData } from '@/types/workout';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ArrowRight, CheckCircle, Sparkles } from 'lucide-react';
import { cn } from '@/lib/utils';

const daysOfWeekMap = [
  { name: "Sunday", value: 0 }, { name: "Monday", value: 1 },
  { name: "Tuesday", value: 2 }, { name: "Wednesday", value: 3 },
  { name: "Thursday", value: 4 }, { name: "Friday", value: 5 },
  { name: "Saturday", value: 6 },
];

function ConfigureDaysComponent() {
  const router = useRouter();
  const searchParams = useSearchParams();

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

  const onSubmit = (data: { days: Partial<WorkoutDay>[] }) => {
    const payload = {
      planName,
      planDescription,
      configuredDays: data.days.map((day, index) => ({
        dayName: `Day ${index + 1}`,
        title: day.title || `Workout Focus ${index + 1}`,
        mapsToActualDayOfWeek: Number(day.mapsToActualDayOfWeek),
      }))
    };
    const query = new URLSearchParams({ data: JSON.stringify(payload) });
    router.push(`/onboarding/create-plan/add-exercises?${query.toString()}`);
  };

  const assignedDays = watch('days').map(d => d.mapsToActualDayOfWeek);

  return (
    <div className="flex flex-col items-center justify-start min-h-screen premium-gradient-bg px-6 py-16">
      <div className="w-full max-w-4xl mb-12 animate-in fade-in slide-in-from-top-4 duration-700">
        <div className="flex items-center gap-4 mb-8 max-w-2xl mx-auto">
          <div className="w-10 h-10 rounded-full bg-primary flex items-center justify-center border border-primary text-background font-bold shadow-lg shadow-primary/20">
            <CheckCircle className="h-6 w-6" />
          </div>
          <div className="flex-1 h-[2px] bg-primary/30 rounded-full relative overflow-hidden">
            <div className="absolute inset-0 bg-primary w-full animate-in slide-in-from-left duration-1000" />
          </div>
          <div className="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center border border-primary/30 text-primary font-bold shadow-lg shadow-primary/10">2</div>
          <div className="flex-1 h-[2px] bg-white/5 rounded-full relative overflow-hidden">
            <div className="absolute inset-0 bg-primary/20 w-1/3" />
          </div>
          <div className="w-10 h-10 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-muted-foreground font-bold font-heading">3</div>
        </div>

        <div className="text-center">
          <h1 className="text-4xl md:text-5xl font-bold tracking-tight mb-4 font-heading">
            Weekly <span className="text-primary">Structure</span>
          </h1>
          <p className="text-muted-foreground text-lg uppercase tracking-widest text-[10px] font-semibold opacity-70">
            Phase 2: Defining Your Split
          </p>
        </div>
      </div>

      <form onSubmit={handleSubmit(onSubmit)} className="w-full max-w-4xl space-y-24 mb-32">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 animate-in fade-in slide-in-from-bottom-8 duration-1000 delay-200 fill-mode-both">
          {fields.map((field, index) => (
            <Card key={field.id} className="glass-panel border-none p-8 rounded-[2.5rem] space-y-6 relative overflow-hidden group">
              <div className="flex items-center justify-between relative z-10">
                <h3 className="text-xl font-bold text-primary font-heading uppercase tracking-tighter italic">Session {index + 1}</h3>
                <div className="p-2 rounded-xl bg-white/5 border border-white/10 opacity-50">
                  <Sparkles className="h-4 w-4" />
                </div>
              </div>

              <div className="space-y-6 relative z-10">
                <div className="space-y-3">
                  <Label htmlFor={`days.${index}.title`} className="text-[10px] uppercase tracking-[0.2em] font-bold opacity-50">Workout Focus*</Label>
                  <Controller
                    name={`days.${index}.title`}
                    control={control}
                    rules={{ required: 'Focus is required' }}
                    render={({ field, fieldState }) => (
                      <>
                        <Input
                          id={`days.${index}.title`}
                          placeholder="e.g., Push (Strength)"
                          className="h-14 bg-white/5 border-white/10 rounded-2xl focus:ring-primary focus:border-primary px-6 transition-all font-medium"
                          {...field}
                        />
                        {fieldState.error && <p className="text-xs text-destructive font-semibold pl-2">{fieldState.error.message}</p>}
                      </>
                    )}
                  />
                </div>

                <div className="space-y-3">
                  <Label htmlFor={`days.${index}.mapsToActualDayOfWeek`} className="text-[10px] uppercase tracking-[0.2em] font-bold opacity-50">Assigned Day</Label>
                  <Controller
                    name={`days.${index}.mapsToActualDayOfWeek`}
                    control={control}
                    render={({ field }) => (
                      <Select onValueChange={field.onChange} defaultValue={String(field.value)}>
                        <SelectTrigger className="h-14 bg-white/5 border-white/10 rounded-2xl px-6 focus:ring-primary focus:border-primary transition-all">
                          <SelectValue placeholder="Assign a day..." />
                        </SelectTrigger>
                        <SelectContent className="glass-panel border-white/10 rounded-2xl overflow-hidden">
                          <SelectItem value="-1" className="hover:bg-white/10 py-3 cursor-pointer">Unassigned (Mobile Only)</SelectItem>
                          {daysOfWeekMap.filter(d => d.value !== -1).map(dayOption => (
                            <SelectItem
                              key={dayOption.value}
                              value={String(dayOption.value)}
                              disabled={assignedDays.includes(dayOption.value) && Number(field.value) !== dayOption.value}
                              className="hover:bg-primary/10 py-3 cursor-pointer"
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

              {/* Decorative background element */}
              <div className="absolute -right-12 -top-12 w-48 h-48 bg-primary/5 rounded-full blur-3xl group-hover:bg-primary/10 transition-colors duration-500" />
            </Card>
          ))}
        </div>

        {/* Floating action button area */}
        <div className="fixed bottom-0 left-0 right-0 p-8 glass-panel border-t border-glass-border flex justify-center z-50 animate-in slide-in-from-bottom-full duration-700 delay-500 fill-mode-both">
          <Button
            type="submit"
            disabled={!isValid}
            className="w-full max-w-sm h-14 rounded-2xl bg-primary hover:bg-primary/90 text-sm font-bold uppercase tracking-widest shadow-2xl shadow-primary/20 interactive-scale"
          >
            Add Exercises to Plan <ArrowRight className="ml-2 h-4 w-4" />
          </Button>
        </div>
      </form>

      <p className="mt-4 text-muted-foreground/30 uppercase tracking-[0.3em] text-[10px] font-bold">
        Step 2 of 3
      </p>
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
