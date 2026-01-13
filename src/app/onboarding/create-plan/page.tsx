// src/app/onboarding/create-plan/page.tsx
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ArrowRight } from 'lucide-react';

const planDetailsSchema = z.object({
  planName: z.string().min(3, { message: "Plan name must be at least 3 characters long." }),
  planDescription: z.string().optional(),
  daysPerWeek: z.string().refine(val => parseInt(val) > 0, { message: "Please select the number of days." }),
});

type PlanDetailsFormValues = z.infer<typeof planDetailsSchema>;

export default function CreatePlanStartPage() {
  const router = useRouter();
  const { control, handleSubmit, formState: { errors, isValid } } = useForm<PlanDetailsFormValues>({
    resolver: zodResolver(planDetailsSchema),
    mode: 'onChange',
    defaultValues: {
      planName: '',
      planDescription: '',
      daysPerWeek: '5',
    }
  });

  const onSubmit = (data: PlanDetailsFormValues) => {
    const query = new URLSearchParams({
      name: data.planName,
      description: data.planDescription || '',
      days: data.daysPerWeek,
    });
    router.push(`/onboarding/create-plan/configure-days?${query.toString()}`);
  };

  return (
    <div className="flex flex-col items-center justify-start min-h-screen premium-gradient-bg px-6 py-16">
      <div className="w-full max-w-2xl mb-12 animate-in fade-in slide-in-from-top-4 duration-700">
        <div className="flex items-center gap-4 mb-8">
          <div className="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center border border-primary/30 text-primary font-bold">1</div>
          <div className="flex-1 h-[2px] bg-white/5 rounded-full relative overflow-hidden">
            <div className="absolute inset-0 bg-primary/20 w-1/3" />
          </div>
          <div className="w-10 h-10 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-muted-foreground font-bold">2</div>
          <div className="flex-1 h-[2px] bg-white/5 rounded-full" />
          <div className="w-10 h-10 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-muted-foreground font-bold">3</div>
        </div>

        <div className="text-center">
          <h1 className="text-4xl md:text-5xl font-bold tracking-tight mb-4 font-heading">
            Design Your <span className="text-primary">Protocol</span>
          </h1>
          <p className="text-muted-foreground text-lg uppercase tracking-widest text-[10px] font-semibold opacity-70">
            Phase 1: Foundation & Frequency
          </p>
        </div>
      </div>

      <Card className="glass-panel border-none w-full max-w-2xl rounded-[2.5rem] overflow-hidden animate-in fade-in slide-in-from-bottom-8 duration-1000 delay-200 fill-mode-both shadow-2xl">
        <CardHeader className="pt-10 pb-4 px-8 md:px-12 text-center md:text-left">
          <CardTitle className="text-2xl font-bold">The Basics</CardTitle>
          <CardDescription>Give your program a name and set your weekly frequency.</CardDescription>
        </CardHeader>
        <form onSubmit={handleSubmit(onSubmit)}>
          <CardContent className="space-y-8 px-8 md:px-12 pb-10">
            <div className="space-y-3">
              <Label htmlFor="planName" className="text-xs uppercase tracking-widest font-bold opacity-70">Program Name*</Label>
              <Controller
                name="planName"
                control={control}
                render={({ field }) => (
                  <Input
                    id="planName"
                    placeholder="e.g., Ultimate Strength Phase 1"
                    className="h-14 bg-white/5 border-white/10 rounded-2xl focus:ring-primary focus:border-primary px-6 transition-all"
                    {...field}
                  />
                )}
              />
              {errors.planName && <p className="text-sm text-destructive font-medium pl-2">{errors.planName.message}</p>}
            </div>

            <div className="space-y-3">
              <Label htmlFor="planDescription" className="text-xs uppercase tracking-widest font-bold opacity-70">Brief Description</Label>
              <Controller
                name="planDescription"
                control={control}
                render={({ field }) => (
                  <Textarea
                    id="planDescription"
                    placeholder="e.g., Focus on heavy compound movements and progressive overload."
                    className="min-h-[120px] bg-white/5 border-white/10 rounded-2xl focus:ring-primary focus:border-primary p-6 transition-all resize-none"
                    {...field}
                  />
                )}
              />
            </div>

            <div className="space-y-3">
              <Label htmlFor="daysPerWeek" className="text-xs uppercase tracking-widest font-bold opacity-70">Weekly Frequency*</Label>
              <Controller
                name="daysPerWeek"
                control={control}
                render={({ field }) => (
                  <Select onValueChange={field.onChange} defaultValue={field.value}>
                    <SelectTrigger id="daysPerWeek" className="h-14 bg-white/5 border-white/10 rounded-2xl px-6 focus:ring-primary focus:border-primary transition-all">
                      <SelectValue placeholder="Select frequency" />
                    </SelectTrigger>
                    <SelectContent className="glass-panel border-white/10 rounded-2xl overflow-hidden">
                      {[...Array(7)].map((_, i) => (
                        <SelectItem
                          key={i + 1}
                          value={String(i + 1)}
                          className="hover:bg-primary/10 py-3 cursor-pointer"
                        >
                          {i + 1} Session{i > 0 ? 's' : ''} Per Week
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              />
              {errors.daysPerWeek && <p className="text-sm text-destructive font-medium pl-2">{errors.daysPerWeek.message}</p>}
            </div>
          </CardContent>

          <div className="p-8 md:p-12 pt-0 flex justify-end">
            <Button
              type="submit"
              disabled={!isValid}
              className="h-14 px-8 rounded-2xl bg-primary hover:bg-primary/90 text-sm font-bold uppercase tracking-widest shadow-xl shadow-primary/20 interactive-scale"
            >
              Continue <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
          </div>
        </form>
      </Card>

      <p className="mt-12 text-muted-foreground/30 uppercase tracking-[0.3em] text-[10px] font-bold">
        Step 1 of 3
      </p>
    </div>
  );
}
