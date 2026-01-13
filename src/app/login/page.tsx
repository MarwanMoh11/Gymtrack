
'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from '@/components/ui/form';
import { Input } from '@/components/ui/input';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/context/auth-context';
import { Dumbbell, Loader2 } from 'lucide-react';
import { Separator } from '@/components/ui/separator';

const loginSchema = z.object({
  email: z.string().email({ message: 'Please enter a valid email.' }),
  password: z.string().min(1, { message: 'Password is required.' }),
});

type LoginFormValues = z.infer<typeof loginSchema>;

const isMobileDevice = () => {
  if (typeof window === 'undefined') return false;
  return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
};

export default function LoginPage() {
  const [isLoading, setIsLoading] = useState(false);
  const [isGoogleLoading, setIsGoogleLoading] = useState(false);
  const [isMobile, setIsMobile] = useState(false);
  const { toast } = useToast();
  const { login, signInWithGoogle } = useAuth();
  const router = useRouter();

  useEffect(() => {
    setIsMobile(isMobileDevice());
  }, []);

  const form = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: {
      email: '',
      password: '',
    },
  });

  const onSubmit = async (data: LoginFormValues) => {
    setIsLoading(true);
    try {
      await login(data.email, data.password);
      toast({
        title: 'Welcome Back',
        description: "Your session has been restored.",
      });
    } catch (error: any) {
      handleAuthError(error, 'Login Failed');
    } finally {
      setIsLoading(false);
    }
  };

  const handleGoogleSignIn = async () => {
    if (isMobile) {
      toast({
        variant: 'destructive',
        title: 'Action Required',
        description: 'Google Sign-In is temporarily limited on mobile. Please use your credentials.',
      });
      return;
    }
    setIsGoogleLoading(true);
    try {
      await signInWithGoogle();
      toast({
        title: 'Welcome Back',
        description: "Signed in with Google.",
      });
    } catch (error: any) {
      handleAuthError(error, 'Sign-In Failed');
    } finally {
      setIsGoogleLoading(false);
    }
  }

  const handleAuthError = (error: any, title: string) => {
    let errorMessage = 'An unexpected error occurred. Please try again.';
    switch (error.code) {
      case 'auth/user-not-found':
      case 'auth/wrong-password':
      case 'auth/invalid-credential':
        errorMessage = 'The credentials provided do not match our records.';
        break;
      case 'auth/invalid-email':
        errorMessage = 'Please enter a valid email address.';
        break;
      case 'auth/too-many-requests':
        errorMessage = 'Too many attempts. Please try again later.';
        break;
      default:
        console.error(title, error);
    }
    toast({
      variant: 'destructive',
      title: title,
      description: errorMessage,
    });
  }

  return (
    <div className="w-full max-w-[420px] px-4">
      <div className="text-center mb-8 animate-in fade-in slide-in-from-bottom-4 duration-700">
        <div className="inline-flex p-3 rounded-2xl bg-primary/10 border border-primary/20 mb-4 interactive-scale">
          <Dumbbell className="h-10 w-10 text-primary" />
        </div>
        <h1 className="text-4xl font-bold tracking-tight mb-2">GymTrack</h1>
        <p className="text-muted-foreground text-lg uppercase tracking-widest text-[10px] font-semibold opacity-70">
          Elevate Your Performance
        </p>
      </div>

      <Card className="glass-panel border-none shadow-none rounded-3xl overflow-hidden animate-in zoom-in-95 fade-in duration-500 delay-200 fill-mode-both">
        <CardHeader className="pt-8 pb-4 text-center">
          <CardTitle className="text-2xl font-bold font-heading">Welcome Back</CardTitle>
          <CardDescription className="text-muted-foreground">
            Sign in to continue your journey
          </CardDescription>
        </CardHeader>
        <CardContent className="px-6 pb-8">
          <Form {...form}>
            <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-5">
              <FormField
                control={form.control}
                name="email"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel className="text-xs uppercase tracking-wider font-semibold opacity-70">Email Address</FormLabel>
                    <FormControl>
                      <Input
                        placeholder="your@email.com"
                        {...field}
                        disabled={isLoading || isGoogleLoading}
                        className="h-12 bg-white/5 border-white/10 rounded-xl focus:ring-primary focus:border-primary transition-all"
                      />
                    </FormControl>
                    <FormMessage className="text-xs" />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="password"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel className="text-xs uppercase tracking-wider font-semibold opacity-70">Password</FormLabel>
                    <FormControl>
                      <Input
                        type="password"
                        placeholder="••••••••"
                        {...field}
                        disabled={isLoading || isGoogleLoading}
                        className="h-12 bg-white/5 border-white/10 rounded-xl focus:ring-primary focus:border-primary transition-all"
                      />
                    </FormControl>
                    <FormMessage className="text-xs" />
                  </FormItem>
                )}
              />
              <Button
                type="submit"
                className="w-full h-12 text-sm font-bold uppercase tracking-widest rounded-xl bg-primary hover:bg-primary/90 transition-all shadow-xl shadow-primary/20 interactive-scale"
                disabled={isLoading || isGoogleLoading}
              >
                {isLoading ? <Loader2 className="h-5 w-5 animate-spin" /> : "Sign In"}
              </Button>
            </form>
          </Form>

          <div className="relative my-8">
            <div className="absolute inset-0 flex items-center">
              <span className="w-full border-t border-white/5" />
            </div>
            <div className="relative flex justify-center text-xs uppercase tracking-tighter">
              <span className="bg-transparent px-4 text-muted-foreground font-medium italic">Alternatively</span>
            </div>
          </div>

          <Button
            variant="outline"
            className="w-full h-12 bg-white/5 border-white/10 hover:bg-white/10 rounded-xl transition-all interactive-scale"
            onClick={handleGoogleSignIn}
            disabled={isLoading || isGoogleLoading || isMobile}
          >
            {isGoogleLoading ? (
              <Loader2 className="h-5 w-5 animate-spin" />
            ) : (
              <div className="flex items-center justify-center gap-3">
                <svg className="h-5 w-5" viewBox="0 0 24 24">
                  <path fill="currentColor" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                  <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                  <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z" />
                  <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                </svg>
                <span className="font-semibold">Sign in with Google</span>
              </div>
            )}
          </Button>

          <div className="mt-8 text-center text-sm">
            <span className="text-muted-foreground">New to GymTrack? </span>
            <Link href="/signup" className="font-bold text-primary hover:underline transition-all">
              Create an account
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
