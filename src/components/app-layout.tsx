// src/components/app-layout.tsx
'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { CalendarCheck, Dumbbell, PanelLeft, TrendingUp, LayoutGrid, LogOut, Settings } from 'lucide-react';
import {
  Sidebar,
  SidebarHeader,
  SidebarContent,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuButton,
  SidebarFooter,
  SidebarInset,
  SidebarTrigger,
  useSidebar,
} from '@/components/ui/sidebar';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Logo } from '@/components/icons/logo';
import { Separator } from '@/components/ui/separator';
import { useAuth } from '@/context/auth-context';
import { useUser } from '@/context/user-context';
import { cn } from '@/lib/utils';

const navigationItems = [
  {
    href: '/dashboard/today',
    icon: CalendarCheck,
    label: "Today",
  },
  {
    href: '/workout-plan',
    icon: LayoutGrid,
    label: 'Plans',
  },
  {
    href: '/dashboard/progressive-overload',
    icon: TrendingUp,
    label: 'Progress',
  },
  {
    href: '/dashboard/settings',
    icon: Settings,
    label: 'Settings',
  }
];

// Loading skeleton for when auth state is being determined
function AuthLoadingSkeleton() {
  return (
    <div className="flex h-screen w-full items-center justify-center bg-background">
      <div className="flex flex-col items-center gap-4">
        <Dumbbell className="h-12 w-12 animate-pulse text-primary" />
        <p className="text-muted-foreground">Initializing session...</p>
      </div>
    </div>
  );
}

function PublicLayout({ children }: { children: React.ReactNode }) {
  return (
    <main className="flex min-h-screen w-full flex-col items-center justify-center bg-background p-4 pt-8 pb-8">
      <div className="w-full flex justify-center items-center">
        {children}
      </div>
    </main>
  );
}

function BottomNav() {
  const pathname = usePathname();

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-50 h-16 glass-panel border-t border-glass-border md:hidden">
      <div className="grid h-full grid-cols-4">
        {navigationItems.map((item) => {
          const isActive = pathname === item.href;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex flex-col items-center justify-center gap-1 transition-colors duration-200",
                isActive ? "text-primary" : "text-muted-foreground hover:text-foreground"
              )}
            >
              <item.icon className={cn("h-6 w-6", isActive && "interactive-scale")} />
              <span className="text-[10px] font-medium uppercase tracking-tighter">{item.label}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}

// Full app layout for authenticated users
function AuthenticatedLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { isMobile, setOpenMobile } = useSidebar();
  const { user, logout } = useAuth();
  const router = useRouter();

  const handleLinkClick = () => {
    if (isMobile) {
      setOpenMobile(false);
    }
  };

  const handleLogout = async () => {
    await logout();
    router.push('/login');
  };

  return (
    <div className="flex h-screen overflow-hidden premium-gradient-bg">
      {/* Desktop Sidebar */}
      <Sidebar variant="sidebar" collapsible="icon" className="hidden md:flex">
        <SidebarHeader className="p-6">
          <div className="flex items-center gap-3">
            <Logo />
            <h1 className="text-xl font-bold tracking-tight text-sidebar-foreground group-data-[collapsible=icon]:hidden">
              GymTrack
            </h1>
          </div>
        </SidebarHeader>
        <SidebarContent>
          <SidebarMenu className="px-4 py-2 gap-2">
            {navigationItems.map((item) => (
              <SidebarMenuItem key={item.href}>
                <SidebarMenuButton
                  asChild
                  isActive={pathname === item.href}
                  variant="default"
                  size="lg"
                  className="rounded-xl"
                  tooltip={item.label}
                >
                  <Link href={item.href} onClick={handleLinkClick}>
                    <item.icon className="h-5 w-5" />
                    <span className="font-medium">{item.label}</span>
                  </Link>
                </SidebarMenuButton>
              </SidebarMenuItem>
            ))}
          </SidebarMenu>
        </SidebarContent>
        <SidebarFooter className="p-6 mt-auto">
          <SidebarMenuButton
            variant="default"
            size="default"
            className="rounded-xl text-destructive hover:text-destructive hover:bg-destructive/10"
            tooltip="Logout"
            onClick={handleLogout}
          >
            <LogOut className="h-5 w-5" />
            <span className="font-medium">Logout</span>
          </SidebarMenuButton>
          <p className="text-[10px] text-muted-foreground mt-4 px-2 truncate group-data-[collapsible=icon]:hidden opacity-50 uppercase tracking-widest">
            {user?.email}
          </p>
        </SidebarFooter>
      </Sidebar>

      {/* Main Content Area */}
      <SidebarInset className="flex flex-col bg-transparent">
        {/* Mobile/Tablet Header */}
        <header className="sticky top-0 z-40 flex h-16 w-full items-center justify-between px-4 sm:px-6 md:px-8 glass-panel border-b border-glass-border">
          <div className="flex items-center gap-3 min-w-0 flex-shrink">
            <div className="p-2 rounded-xl bg-primary/10 border border-primary/20">
              <Dumbbell className="h-6 w-6 text-primary" />
            </div>
            <h1 className="text-lg font-bold tracking-tight uppercase">
              {navigationItems.find(item => pathname === item.href)?.label || "GymTrack"}
            </h1>
          </div>
          <div className="flex items-center gap-2 flex-shrink-0">
            <Button
              variant="ghost"
              size="icon"
              className="rounded-xl text-muted-foreground hover:text-destructive hover:bg-destructive/10 transition-colors"
              onClick={handleLogout}
              title="Logout"
            >
              <LogOut className="h-5 w-5" />
            </Button>
          </div>
        </header>

        <main className="flex-1 pb-24 md:pb-8 pt-6 sm:pt-8 overflow-y-auto">
          <div className="max-w-5xl mx-auto px-6 md:px-12">
            {children}
          </div>
        </main>
      </SidebarInset>

      {/* Mobile Navigation Bar */}
      <BottomNav />
    </div>
  );
}

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { user, loading: isAuthLoading, isProcessingRedirect } = useAuth();
  const pathname = usePathname();
  const router = useRouter();

  const publicRoutes = ['/login', '/signup'];
  const onboardingRoutes = ['/onboarding/welcome', '/onboarding/choose-plan'];
  const planCreationRoutes = ['/onboarding/create-plan', '/onboarding/create-plan/configure-days', '/onboarding/create-plan/add-exercises'];

  const isPublicRoute = publicRoutes.includes(pathname);
  const isOnboardingRoute = onboardingRoutes.some(route => pathname.startsWith(route));
  const isPlanCreationRoute = planCreationRoutes.some(route => pathname.startsWith(route));

  const { userData, isLoading: isLoadingUserData, error: userError } = useUser();

  useEffect(() => {
    console.log("[AppLayout] Effect running", {
      user: !!user,
      userData: !!userData,
      status: userData?.onboardingStatus,
      isAuthLoading,
      isLoadingUserData,
      pathname,
      isPublicRoute,
      isOnboardingRoute
    });

    // Wait until all auth-related loading is complete.
    if (isAuthLoading || isProcessingRedirect) {
      return;
    }

    // Logic for unauthenticated users
    if (!user) {
      if (!isPublicRoute) {
        router.replace('/login');
      }
      return;
    }

    // For authenticated users, ensure they aren't on a public route.
    if (user && isPublicRoute) {
      if (isLoadingUserData) return;
      if (userData) {
        if (userData.onboardingStatus === 'completed') {
          router.replace('/dashboard/today');
        } else {
          router.replace('/onboarding/welcome');
        }
      } else {
        // Authenticated but no data - should be initialized by UserProvider, but fallback redirect to onboarding.
        router.replace('/onboarding/welcome');
      }
      return;
    }

    // Logic for users with data
    if (user && userData) {
      if (userData.onboardingStatus === 'needs_plan_selection') {
        if (!isOnboardingRoute && !isPlanCreationRoute) {
          router.replace('/onboarding/welcome');
        }
      } else if (userData.onboardingStatus === 'completed') {
        const isAllowedRouteForCompletedUser =
          pathname.startsWith('/dashboard') ||
          pathname.startsWith('/workout-plan') ||
          pathname.startsWith('/exercises') ||
          isPlanCreationRoute;

        if (!isAllowedRouteForCompletedUser) {
          router.replace('/dashboard/today');
        }
      }
    } else if (!isPublicRoute && user && !isLoadingUserData && !userData) {
      // Authenticated but document missing (e.g. after a purge).
      console.log("No user data found for authenticated user, redirecting to onboarding...");
      router.replace('/onboarding/welcome');
    }

  }, [user, userData, isAuthLoading, isLoadingUserData, userError, isProcessingRedirect, pathname, isPublicRoute, isOnboardingRoute, isPlanCreationRoute, router]);

  // --- Render Logic ---
  const isLoading = isAuthLoading || isProcessingRedirect || (!!user && isLoadingUserData);

  if (userError) {
    console.error("[AppLayout] userError detected", userError);
    return (
      <div className="flex h-screen w-full flex-col items-center justify-center p-4 bg-background text-center">
        <Dumbbell className="h-12 w-12 text-destructive mb-4" />
        <h2 className="text-xl font-bold mb-2 uppercase italic">Initialization Failed</h2>
        <p className="text-muted-foreground text-sm max-w-xs mb-6">We couldn't initialize your training protocol. This may be due to a connection issue.</p>
        <Button onClick={() => window.location.reload()} variant="outline" className="rounded-xl border-primary/20 hover:bg-primary/10">
          Force Re-Initialize
        </Button>
      </div>
    );
  }

  if (isLoading) {
    console.log("[AppLayout] Rendering AuthLoadingSkeleton (isLoading)", { isAuthLoading, isProcessingRedirect, isLoadingUserData });
    return <AuthLoadingSkeleton />;
  }

  if (user && isPublicRoute) {
    console.log("[AppLayout] Rendering AuthLoadingSkeleton (auth user on public route)");
    return <AuthLoadingSkeleton />;
  }

  if (user && userData) {
    console.log("[AppLayout] User and UserData found", { status: userData.onboardingStatus, pathname });
    if (userData.onboardingStatus === 'needs_plan_selection') {
      const canRender = isOnboardingRoute || isPlanCreationRoute;
      console.log("[AppLayout] Onboarding status: needs_plan_selection", { canRender });
      return canRender ? <>{children}</> : <AuthLoadingSkeleton />;
    }
    if (userData.onboardingStatus === 'completed') {
      const isAllowedRouteForCompletedUser = pathname.startsWith('/dashboard') || pathname.startsWith('/workout-plan') || pathname.startsWith('/exercises') || isPlanCreationRoute;
      console.log("[AppLayout] Onboarding status: completed", { isAllowedRouteForCompletedUser });
      return isAllowedRouteForCompletedUser
        ? <AuthenticatedLayout>{children}</AuthenticatedLayout>
        : <AuthLoadingSkeleton />;
    }
    console.log("[AppLayout] Unhandled onboarding status", { status: userData.onboardingStatus });
  }

  if (!user && isPublicRoute) {
    console.log("[AppLayout] Rendering PublicLayout");
    return <PublicLayout>{children}</PublicLayout>;
  }

  console.log("[AppLayout] Final fallback to AuthLoadingSkeleton", { user: !!user, userData: !!userData });
  return <AuthLoadingSkeleton />;
}
