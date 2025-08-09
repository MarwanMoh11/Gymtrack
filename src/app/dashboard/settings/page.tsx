// src/app/dashboard/settings/page.tsx
'use client';
import { Suspense } from 'react';
import LoadingSettingsPage from './loading';
import SettingsForm from '@/components/dashboard/settings-form';

export default function SettingsPage() {
    return (
        <Suspense fallback={<LoadingSettingsPage />}>
            <SettingsForm />
        </Suspense>
    )
}