'use client';
// src/app/onboarding/welcome/page.tsx
import Link from 'next/link';
import { useState } from 'react';
import { useAuth } from '@/context/auth-context';
import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Dumbbell, ArrowRight, Sparkles, LayoutGrid, PenTool, LogOut, Loader2 } from 'lucide-react';

export default function WelcomePage() {
  const { logout } = useAuth();
  const [isLoggingOut, setIsLoggingOut] = useState(false);

  const handleLogout = async () => {
    setIsLoggingOut(true);
    try {
      await logout();
    } finally {
      setIsLoggingOut(false);
    }
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-background px-4 py-8 relative overflow-hidden">
      {/* Logout Button */}
      <div className="absolute top-6 right-6 z-50 animate-in fade-in slide-in-from-top-4 duration-1000 delay-500 fill-mode-both">
        <Button
          variant="ghost"
          size="sm"
          className="rounded-xl text-muted-foreground hover:text-destructive hover:bg-destructive/10 gap-2 px-4 py-2 border border-white/5 transition-all duration-300"
          onClick={handleLogout}
          disabled={isLoggingOut}
        >
          {isLoggingOut ? <Loader2 className="h-4 w-4 animate-spin" /> : <LogOut className="h-4 w-4" />}
          <span>Sign Out</span>
        </Button>
      </div>
      {/* Decorative background effects */}
      <div className="absolute top-0 left-0 w-full h-full bg-[radial-gradient(circle_at_50%_50%,rgba(163,255,18,0.03),transparent_70%)] pointer-events-none" />

      <div className="w-full max-w-xl text-center mb-12 animate-in fade-in slide-in-from-bottom-6 duration-1000 relative z-10">
        <div className="inline-flex p-6 rounded-[2.5rem] bg-primary/10 border border-primary/20 mb-10 interactive-scale shadow-2xl shadow-primary/5">
          <Dumbbell className="h-16 w-16 text-primary" />
        </div>
        <h1 className="text-5xl md:text-7xl font-black tracking-tighter mb-4 font-heading uppercase italic">
          Gym<span className="text-primary italic">Track</span>
        </h1>
        <p className="text-muted-foreground text-lg md:text-xl font-medium max-w-sm mx-auto leading-relaxed opacity-60">
          Your path to peak performance starts with an architectural protocol.
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-6 w-full max-w-3xl animate-in zoom-in-95 fade-in duration-700 delay-300 fill-mode-both relative z-10">
        <Link href="/onboarding/choose-plan" className="group">
          <Card className="glass-panel border-none h-full hover:bg-white/5 transition-all duration-500 rounded-[2.5rem] overflow-hidden interactive-scale shadow-xl shadow-black/40">
            <CardHeader className="pt-12 pb-8 text-center">
              <div className="mx-auto w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mb-6 group-hover:scale-110 group-hover:bg-primary/20 transition-all duration-500 border border-primary/10">
                <LayoutGrid className="h-8 w-8 text-primary" />
              </div>
              <CardTitle className="text-2xl font-black tracking-tight uppercase italic group-hover:text-primary transition-colors">Pick a Plan</CardTitle>
              <CardDescription className="text-muted-foreground mt-3 font-medium text-xs opacity-60">
                Start immediately with one of our expert templates
              </CardDescription>
            </CardHeader>
            <CardFooter className="justify-center pb-12">
              <div className="flex items-center text-primary font-black uppercase tracking-[0.2em] text-[10px] bg-primary/5 px-4 py-2 rounded-full border border-primary/10">
                Fast Track <ArrowRight className="ml-2 h-4 w-4 group-hover:translate-x-1 transition-transform" />
              </div>
            </CardFooter>
          </Card>
        </Link>

        <Link href="/onboarding/create-plan" className="group">
          <Card className="glass-panel border-none h-full hover:bg-white/5 transition-all duration-500 rounded-[2.5rem] overflow-hidden interactive-scale shadow-xl shadow-black/40">
            <CardHeader className="pt-12 pb-8 text-center">
              <div className="mx-auto w-16 h-16 rounded-2xl bg-white/5 flex items-center justify-center mb-6 group-hover:scale-110 group-hover:bg-white/10 transition-all duration-500 border border-white/5">
                <PenTool className="h-8 w-8 text-foreground/40 group-hover:text-foreground transition-colors" />
              </div>
              <CardTitle className="text-2xl font-black tracking-tight uppercase italic group-hover:text-primary transition-colors">Custom Build</CardTitle>
              <CardDescription className="text-muted-foreground mt-3 font-medium text-xs opacity-60">
                Create a tailor-made plan from the ground up
              </CardDescription>
            </CardHeader>
            <CardFooter className="justify-center pb-12">
              <div className="flex items-center text-muted-foreground font-black uppercase tracking-[0.2em] text-[10px] bg-white/5 px-4 py-2 rounded-full border border-white/5">
                Manual Setup <ArrowRight className="ml-2 h-4 w-4 group-hover:translate-x-1 transition-transform" />
              </div>
            </CardFooter>
          </Card>
        </Link>
      </div>

      <div className="mt-16 flex flex-col items-center gap-2 animate-in fade-in duration-1000 delay-1000 fill-mode-both relative z-10">
        <p className="text-[10px] font-black uppercase tracking-[0.4em] text-foreground/20">
          Designed for Excellence
        </p>
        <div className="h-px w-8 bg-primary/20" />
      </div>
    </div>
  );
}
