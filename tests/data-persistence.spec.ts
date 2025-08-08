import { test, expect } from '@playwright/test';

test.describe('Firestore Data Persistence', () => {

  // Use a unique email for each test run to ensure isolation
  const userEmail = `test-user-${Date.now()}@example.com`;
  const userPassword = 'password123';

  // Sign up and log in before running the tests.
  test.beforeAll(async ({ browser }) => {
    const page = await browser.newPage();
    await page.goto('/signup');
    await page.getByLabel('Email').fill(userEmail);
    await page.getByLabel('Password', { exact: true }).fill(userPassword);
    await page.getByLabel('Confirm Password').fill(userPassword);
    await page.getByRole('button', { name: 'Create Account' }).click();
    // Wait for the app to redirect to the dashboard, indicating successful signup/login.
    await expect(page).toHaveURL('/dashboard/today', { timeout: 20000 });
    await page.close();
  });
  
  // Clean up user by logging out after tests.
  // Note: In a real-world scenario, you might have a backend helper to delete test users.
  test.afterAll(async ({ browser }) => {
     const page = await browser.newPage();
     await page.goto('/dashboard/today'); // Go to a page within the app
     await page.getByRole('button', { name: 'Logout' }).click();
     await expect(page).toHaveURL('/login');
     await page.close();
  });

  test('should log an exercise set, persist it in Firestore, and display it in history', async ({ page }) => {
    // 1. Log in with the created user
    await page.goto('/login');
    await page.getByLabel('Email').fill(userEmail);
    await page.getByLabel('Password').fill(userPassword);
    await page.getByRole('button', { name: 'Sign In' }).click();
    await expect(page).toHaveURL('/dashboard/today', { timeout: 10000 });

    // 2. Navigate to the first exercise of the 'Today\'s Session'
    // Add a specific expectation for the exercise card to ensure data has loaded from Firestore.
    const exerciseCard = page.locator('div.space-y-4 > div.shadow-md').first();
    await expect(exerciseCard).toBeVisible({ timeout: 15000 });
    
    const exerciseLink = exerciseCard.getByRole('link', { name: /Log \/ View/ });
    await expect(exerciseLink).toBeVisible();
    await exerciseLink.click();

    // 3. Wait for the exercise detail page to load
    await expect(page).toHaveURL(/\/exercises\//, { timeout: 10000 });
    await expect(page.getByRole('heading', { name: /Log Your Sets/ })).toBeVisible();

    // 4. Log a set
    const repsInput = page.getByLabel('Reps for set 1');
    await repsInput.fill('10');
    const logButton = page.getByRole('button', { name: 'Log' }).first();
    await logButton.click();

    // 5. Verify the set was logged correctly on the page
    await expect(page.locator('div:has-text("Logged: 10 reps")')).toBeVisible();

    // 6. Navigate away to test persistence
    await page.getByRole('link', { name: /Today's Session/ }).click();
    await expect(page.getByRole('heading', { name: /Exercises for Today/ })).toBeVisible();

    // 7. Navigate back to the exercise and verify the data is still there
    await page.locator('div.space-y-4 > div.shadow-md').first().getByRole('link', { name: /Log \/ View/ }).click();
    await expect(page.locator('div:has-text("Logged: 10 reps")')).toBeVisible();

    // 8. Navigate to the progress history page
    await page.getByRole('link', { name: /Progress Dashboard/ }).click();
    await expect(page.getByRole('heading', { name: 'Workout Log Calendar' })).toBeVisible();

    // 9. Check the calendar to see if the day is marked as logged
    const today = new Date();
    const dayOfMonth = today.getDate();
    const calendarCell = page.locator('div.rdp-cell').filter({ hasText: new RegExp(`^${dayOfMonth}$`) });
    
    // Updated check: Ensure the button inside the cell is no longer disabled, which indicates it's logged.
    await expect(calendarCell.locator(`button[aria-label*="${today.toLocaleString('default', { month: 'long' })}"]`)).not.toBeDisabled();
    
    // 10. Click the logged day to view the details
    await calendarCell.click();
    await expect(page.getByRole('heading', { name: /Workout Log:/ })).toBeVisible({ timeout: 10000 });
    
    // 11. Verify the logged exercise appears in the modal
    await expect(page.locator('div[role="dialog"]').locator('div:has-text("Set 1:")')).toContainText('10 reps');
  });

});
