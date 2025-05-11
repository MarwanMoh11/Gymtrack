// src/components/dashboard/progress-chart.tsx
'use client';

import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  DotProps,
} from 'recharts';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useTheme } from 'next-themes'; // To get current theme for colors
import { useMemo } from 'react';

export interface ChartDataPoint {
  date: string; // YYYY-MM-DD
  weight: number;
  type: 'actual' | 'target';
  isPR?: boolean;
  reps?: number | string; // Optional: for tooltip
}

interface ProgressChartProps {
  actualData: ChartDataPoint[];
  targetData: ChartDataPoint[];
  exerciseName: string;
}

const CustomDot = (props: DotProps & { isPR?: boolean; payload?: ChartDataPoint }) => {
  const { cx, cy, stroke, fill, r, isPR, payload } = props;

  if (!cx || !cy) return null;

  if (isPR && payload?.type === 'actual') {
    return (
      <svg x={cx - 6} y={cy - 6} width={12} height={12} fill="hsl(var(--primary))" viewBox="0 0 1024 1024">
        <circle cx={cx} cy={cy} r={(r || 3) + 3} fill="hsl(var(--primary) / 0.3)" />
        <circle cx={cx} cy={cy} r={r || 3} stroke="hsl(var(--primary-foreground))" fill="hsl(var(--primary))" strokeWidth={1} className="pr-dot"/>
      </svg>
    );
  }
  // Regular dot for actual data or target data
  if (payload?.type === 'actual') {
     return <circle cx={cx} cy={cy} r={r || 3} stroke={stroke} fill={fill} strokeWidth={1} />;
  }
  return null; // Don't render dots for target line, or make them different
};


export function ProgressChart({ actualData, targetData, exerciseName }: ProgressChartProps) {
  const { theme } = useTheme();

  const colors = useMemo(() => {
    const style = getComputedStyle(document.documentElement);
    return {
      foreground: style.getPropertyValue('--foreground'), // Or a specific text color
      primary: style.getPropertyValue('--primary'),
      mutedForeground: style.getPropertyValue('--muted-foreground'),
      card: style.getPropertyValue('--card'),
      border: style.getPropertyValue('--border'),
    };
  }, [theme]); // Re-calculate if theme changes, though HSL vars should update CSS

  const combinedData = useMemo(() => {
    const allDataPoints: { [date: string]: Partial<ChartDataPoint> & { actualWeight?: number; targetWeight?: number; date: string, isPR?: boolean, reps?: string | number } } = {};

    actualData.forEach(p => {
      if (!allDataPoints[p.date]) allDataPoints[p.date] = { date: p.date };
      allDataPoints[p.date].actualWeight = p.weight;
      allDataPoints[p.date].isPR = p.isPR;
      allDataPoints[p.date].reps = p.reps;
    });

    targetData.forEach(p => {
      if (!allDataPoints[p.date]) allDataPoints[p.date] = { date: p.date };
      allDataPoints[p.date].targetWeight = p.weight;
    });
    
    return Object.values(allDataPoints).sort((a,b) => new Date(a.date).getTime() - new Date(b.date).getTime());

  }, [actualData, targetData]);

  if (actualData.length === 0 && targetData.length === 0) {
    return (
      <Card className="shadow-xl rounded-2xl">
        <CardHeader>
          <CardTitle className="text-2xl font-bold text-primary">Progress: {exerciseName}</CardTitle>
          <CardDescription>No data available to display chart.</CardDescription>
        </CardHeader>
        <CardContent className="h-64 flex items-center justify-center">
          <p className="text-muted-foreground">Log some workouts to see your progress!</p>
        </CardContent>
      </Card>
    );
  }
  
  const yAxisDomain = useMemo(() => {
    const allWeights = [...actualData.map(p => p.weight), ...targetData.map(p => p.weight)];
    if (allWeights.length === 0) return [0, 'auto'];
    const minWeight = Math.min(...allWeights);
    const maxWeight = Math.max(...allWeights);
    return [Math.floor(minWeight * 0.9), Math.ceil(maxWeight * 1.1)];
  }, [actualData, targetData]);


  return (
    <Card className="shadow-xl rounded-2xl">
      <CardHeader>
        <CardTitle className="text-2xl font-bold text-primary">Progress: {exerciseName}</CardTitle>
        <CardDescription>Your weight progression over time.</CardDescription>
      </CardHeader>
      <CardContent className="h-[400px] pr-4">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={combinedData} margin={{ top: 5, right: 10, left: 0, bottom: 5 }}>
            <CartesianGrid strokeDasharray="3 3" stroke={`hsl(${colors.border})`} opacity={0.5} />
            <XAxis 
              dataKey="date" 
              stroke={`hsl(${colors.mutedForeground})`}
              tickFormatter={(tick) => new Date(tick).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
              padding={{ left: 10, right: 10 }}
            />
            <YAxis 
              stroke={`hsl(${colors.mutedForeground})`}
              domain={yAxisDomain}
              label={{ value: 'Weight (kg)', angle: -90, position: 'insideLeft', fill: `hsl(${colors.mutedForeground})`, dy: 40, dx: -5, fontSize: 12 }}
              />
            <Tooltip
              contentStyle={{ 
                backgroundColor: `hsl(${colors.card})`, 
                borderColor: `hsl(${colors.border})`,
                borderRadius: '0.5rem',
                boxShadow: '0 4px 6px -1px rgba(0,0,0,0.1), 0 2px 4px -1px rgba(0,0,0,0.06)'
              }}
              labelStyle={{ color: `hsl(${colors.foreground})`, fontWeight: 'bold' }}
              itemStyle={{ color: `hsl(${colors.foreground})` }}
              formatter={(value, name, props) => {
                const originalPoint = actualData.find(p => p.date === props.payload.date && p.weight === value) || targetData.find(p => p.date === props.payload.date && p.weight === value);
                let displayValue = `${value} kg`;
                if (originalPoint?.type === 'actual' && props.payload.reps) {
                  displayValue += ` for ${props.payload.reps} reps`;
                }
                if (originalPoint?.isPR) {
                  displayValue += " (PR!)";
                }
                return [displayValue, name === 'actualWeight' ? 'Logged Weight' : 'Target Weight'];
              }}
            />
            <Legend wrapperStyle={{ color: `hsl(${colors.foreground})`}} />
            <Line
              type="monotone"
              dataKey="actualWeight"
              name="Logged Weight"
              stroke={`hsl(${colors.primary})`}
              strokeWidth={2.5}
              dot={(props) => <CustomDot {...props} isPR={props.payload.isPR} payload={props.payload as ChartDataPoint} />}
              activeDot={{ r: 6, strokeWidth: 1, fill: `hsl(${colors.primary})` }}
            />
            <Line
              type="monotone"
              dataKey="targetWeight"
              name="Target Progression"
              stroke={`hsl(${colors.foreground})`}
              strokeWidth={2}
              strokeDasharray="5 5"
              dot={false}
              activeDot={{ r: 5 }}
              opacity={0.7}
            />
          </LineChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  );
}
