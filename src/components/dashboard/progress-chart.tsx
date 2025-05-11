
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
  type DotProps,
} from 'recharts';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useTheme } from 'next-themes'; 
import { useMemo, useEffect, useState } from 'react';

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

  if (cx === undefined || cy === undefined) return null; // Check if cx or cy is undefined

  if (isPR && payload?.type === 'actual') {
    return (
      <g> {/* Use <g> to group elements if needed, or directly return SVG elements */}
        <circle cx={cx} cy={cy} r={(r || 3) + 3} fill="hsl(var(--primary) / 0.3)" />
        <circle cx={cx} cy={cy} r={r || 3} stroke="hsl(var(--primary-foreground))" fill="hsl(var(--primary))" strokeWidth={1} className="pr-dot"/>
      </g>
    );
  }
  // Regular dot for actual data
  if (payload?.type === 'actual') {
     return <circle cx={cx} cy={cy} r={r || 3} stroke={stroke} fill={fill} strokeWidth={1} />;
  }
  return null; // Don't render dots for target line by default
};


export function ProgressChart({ actualData, targetData, exerciseName }: ProgressChartProps) {
  const { theme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);


  const colors = useMemo(() => {
    if (typeof window === 'undefined' || !mounted) { // Ensure document is available and component mounted
        // Provide default/fallback colors for SSR or pre-mount
        return {
            foreground: 'hsl(0 0% 100%)',
            primary: 'hsl(84 100% 53.5%)',
            mutedForeground: 'hsl(0 0% 65%)',
            card: 'hsl(240 5% 10%)',
            border: 'hsl(240 5% 20%)',
        };
    }
    const style = getComputedStyle(document.documentElement);
    return {
      foreground: style.getPropertyValue('--foreground').trim(), 
      primary: style.getPropertyValue('--primary').trim(),
      mutedForeground: style.getPropertyValue('--muted-foreground').trim(),
      card: style.getPropertyValue('--card').trim(),
      border: style.getPropertyValue('--border').trim(),
    };
  }, [theme, mounted]);

  const combinedData = useMemo(() => {
    const allDataPointsMap: { [date: string]: { date: string, actualWeight?: number; targetWeight?: number; isPR?: boolean, reps?: string | number } } = {};

    actualData.forEach(p => {
      if (!allDataPointsMap[p.date]) allDataPointsMap[p.date] = { date: p.date };
      allDataPointsMap[p.date].actualWeight = p.weight;
      allDataPointsMap[p.date].isPR = p.isPR;
      allDataPointsMap[p.date].reps = p.reps;
    });

    targetData.forEach(p => {
      if (!allDataPointsMap[p.date]) allDataPointsMap[p.date] = { date: p.date };
      allDataPointsMap[p.date].targetWeight = p.weight;
    });
    
    return Object.values(allDataPointsMap).sort((a,b) => new Date(a.date).getTime() - new Date(b.date).getTime());

  }, [actualData, targetData]);

  const yAxisDomain = useMemo(() => {
    const allWeights = [
        ...actualData.map(p => p.weight), 
        ...targetData.map(p => p.weight)
    ].filter(w => typeof w === 'number' && !isNaN(w)); // Ensure only valid numbers

    if (allWeights.length === 0) return [0, 50]; // Default domain if no valid weights

    const minWeight = Math.min(...allWeights);
    const maxWeight = Math.max(...allWeights);
    
    const lowerBound = Math.max(0, Math.floor(minWeight * 0.9)); // Ensure lower bound is not negative
    const upperBound = Math.ceil(maxWeight * 1.1) || 50; // Ensure upper bound has a sensible default

    return [lowerBound, upperBound];
  }, [actualData, targetData]);


  if (!mounted) { // Prevents rendering chart before client-side theme and styles are confirmed
      return (
        <Card className="shadow-xl rounded-2xl">
          <CardHeader>
            <CardTitle className="text-2xl font-bold text-primary">Progress: {exerciseName}</CardTitle>
            <CardDescription>Loading chart data...</CardDescription>
          </CardHeader>
          <CardContent className="h-[400px] flex items-center justify-center">
            <p className="text-muted-foreground">Initializing chart...</p>
          </CardContent>
        </Card>
      );
  }

  if (actualData.length === 0 && targetData.length === 0) {
    return (
      <Card className="shadow-xl rounded-2xl">
        <CardHeader>
          <CardTitle className="text-2xl font-bold text-primary">Progress: {exerciseName}</CardTitle>
          <CardDescription>No data available to display chart.</CardDescription>
        </CardHeader>
        <CardContent className="h-[400px] flex items-center justify-center">
          <p className="text-muted-foreground">Log some workouts to see your progress!</p>
        </CardContent>
      </Card>
    );
  }
  

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
              tickFormatter={(tick) => new Date(tick).toLocaleDateString(typeof navigator !== 'undefined' ? navigator.language : 'en-US', { month: 'short', day: 'numeric' })}
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
                // The payload here is an item from `combinedData`
                const pointPayload = props.payload as { date: string, actualWeight?: number; targetWeight?: number; isPR?: boolean, reps?: string | number };
                let displayValue = `${value} kg`;
                if (name === 'actualWeight' && pointPayload.reps) {
                  displayValue += ` for ${pointPayload.reps} reps`;
                }
                if (pointPayload.isPR && name === 'actualWeight') {
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
              dot={(dotElementProps: DotProps) => {
                // Ensure payload is correctly typed based on combinedData structure
                const itemPayload = dotElementProps.payload as (ChartDataPoint & { actualWeight?: number, targetWeight?: number });
                const { key, ...restOfDotElementProps } = dotElementProps; // Destructure key
                // Pass necessary props to CustomDot. isPR comes from the itemPayload.
                return <CustomDot {...restOfDotElementProps} payload={itemPayload} isPR={itemPayload?.isPR} />;
              }}
              activeDot={{ r: 6, strokeWidth: 1, fill: `hsl(${colors.primary})` }}
              connectNulls={false} // Do not connect nulls for actual data
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
              connectNulls={false} // Do not connect nulls for target data
            />
          </LineChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  );
}

