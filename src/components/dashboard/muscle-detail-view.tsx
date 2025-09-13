// src/components/dashboard/muscle-detail-view.tsx
import { useMemo } from 'react';
import { Card, CardHeader, CardTitle, CardContent, CardDescription } from '@/components/ui/card';
import { ChartContainer, ChartTooltip, ChartTooltipContent } from '@/components/ui/chart';
import { LineChart, Line, XAxis, YAxis, CartesianGrid } from 'recharts';
import { Badge } from '@/components/ui/badge';
import type { DailyLog, NamedWorkoutPlan } from '@/types/workout';
import { calculateProgressDataForChart, ChartData } from '@/lib/workout-utils';
import { Target } from 'lucide-react';

interface MuscleDetailViewProps {
  muscle: string;
  volume: number;
  allLogs: Map<string, DailyLog>;
  activePlan: NamedWorkoutPlan;
}

export default function MuscleDetailView({ muscle, volume, allLogs, activePlan }: MuscleDetailViewProps) {
  const exercisesForMuscle = useMemo(() => {
    const exercises: { id: string; name: string; chartData: ChartData[] }[] = [];
    const seenIds = new Set<string>();

    activePlan?.plan.forEach(day => {
      day.exercises.forEach(ex => {
        if (ex.muscleGroups?.includes(muscle) && !ex.isCore && !ex.isActivity && !seenIds.has(ex.id)) {
          const chartData = calculateProgressDataForChart(ex.id, allLogs);
          if (chartData.length > 1) {
            exercises.push({ id: ex.id, name: ex.name, chartData });
            seenIds.add(ex.id);
          }
        }
      });
    });
    return exercises;
  }, [muscle, allLogs, activePlan]);

  const chartConfig = {
    weight: { label: 'Weight (kg)', color: 'hsl(var(--primary))' },
  };

  return (
    <Card className="shadow-lg rounded-2xl">
      <CardHeader>
        <div className="flex items-center gap-3">
          <Target className="h-6 w-6 text-primary" />
          <CardTitle className="text-xl font-semibold">
            Details for: <span className="text-primary">{muscle}</span>
          </CardTitle>
        </div>
        <CardDescription>
          You've performed <Badge variant="secondary">{volume}</Badge> sets targeting this muscle in the last 7 days.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {exercisesForMuscle.length > 0 ? (
          exercisesForMuscle.map(ex => (
            <div key={ex.id}>
              <h4 className="font-semibold text-md mb-2">{ex.name}</h4>
              <ChartContainer config={chartConfig} className="min-h-[150px] w-full">
                <LineChart data={ex.chartData} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
                  <CartesianGrid vertical={false} strokeDasharray="3 3" stroke="hsl(var(--border) / 0.5)" />
                  <XAxis dataKey="date" tick={{ fill: 'hsl(var(--muted-foreground))', fontSize: 10 }} tickLine={false} axisLine={false} />
                  <YAxis domain={['dataMin - 2', 'dataMax + 2']} tick={{ fill: 'hsl(var(--muted-foreground))', fontSize: 10 }} tickLine={false} axisLine={false} />
                  <ChartTooltip
                    cursor={false}
                    content={
                      <ChartTooltipContent
                        formatter={(value, name, props) => (
                           <div className="text-xs">
                             <div>Weight: {value} kg</div>
                             <div>Reps: {props.payload.reps}</div>
                           </div>
                        )}
                      />
                    }
                  />
                  <Line type="monotone" dataKey="weight" stroke="hsl(var(--primary))" strokeWidth={2} dot={(props) => {
                    const { cx, cy, payload } = props;
                    return <circle cx={cx} cy={cy} r={payload.isPR ? 4 : 2} fill="hsl(var(--primary))" />;
                  }} />
                </LineChart>
              </ChartContainer>
            </div>
          ))
        ) : (
          <p className="text-muted-foreground text-center py-4">
            No exercises with sufficient progression data found for this muscle group in your active plan. Log at least two sessions for an exercise to see its chart here.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
