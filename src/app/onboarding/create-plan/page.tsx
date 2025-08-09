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
    <div className="flex flex-col items-center justify-center min-h-screen bg-background p-4">
      <Card className="w-full max-w-2xl">
        <CardHeader>
          <CardTitle className="text-2xl font-bold text-primary">Build Your Own Plan: Step 1</CardTitle>
          <CardDescription>Let's start with the basics. Give your new plan a name and tell us how often you'll work out.</CardDescription>
        </CardHeader>
        <form onSubmit={handleSubmit(onSubmit)}>
          <CardContent className="space-y-6">
            <div className="space-y-2">
              <Label htmlFor="planName">Plan Name*</Label>
              <Controller
                name="planName"
                control={control}
                render={({ field }) => <Input id="planName" placeholder="e.g., My Hypertrophy Program" {...field} />}
              />
              {errors.planName && <p className="text-sm text-destructive">{errors.planName.message}</p>}
            </div>
            <div className="space-y-2">
              <Label htmlFor="planDescription">Plan Description</Label>
              <Controller
                name="planDescription"
                control={control}
                render={({ field }) => <Textarea id="planDescription" placeholder="e.g., A 5-day split focusing on muscle growth and strength." {...field} />}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="daysPerWeek">Workout Days Per Week*</Label>
              <Controller
                name="daysPerWeek"
                control={control}
                render={({ field }) => (
                  <Select onValueChange={field.onChange} defaultValue={field.value}>
                    <SelectTrigger id="daysPerWeek">
                      <SelectValue placeholder="Select number of days" />
                    </SelectTrigger>
                    <SelectContent>
                      {[...Array(7)].map((_, i) => (
                        <SelectItem key={i + 1} value={String(i + 1)}>{i + 1} day{i > 0 ? 's' : ''}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              />
               {errors.daysPerWeek && <p className="text-sm text-destructive">{errors.daysPerWeek.message}</p>}
            </div>
          </CardContent>
          <CardFooter className="flex justify-end">
            <Button type="submit" disabled={!isValid}>
              Next: Configure Days <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
          </CardFooter>
        </form>
      </Card>
    </div>
  );
}
