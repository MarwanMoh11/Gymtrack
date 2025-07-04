import { test, expect } from '@playwright/test';

test.describe('Progressive Overload Weight Change', () => {

  test.beforeEach(async ({ page }) => {
    // Clear localStorage before each test to ensure a clean slate
    await page.goto('/'); // Go to a page to be able to run script
    await page.evaluate(() => localStorage.clear());
  });

  test('should allow user to update target weight and reset sets', async ({ page }) => {
    // This test uses an exercise from the default active plan.
    const exerciseId = 'ogcb-d1-ex3'; // Incline Dumbbell Press
    const dayId = 'ogcb-day1';
    const initialWeight = 'Moderate';
    const newWeight = '25 kg';

    // 1. Navigate to the specific exercise page.
    await page.goto(`/exercises/${exerciseId}?dayId=${dayId}`);

    // 2. Find the weight display section and verify the initial weight.
    const weightDisplaySection = page.locator('div:has(> label:has-text("Planned Weight for Today"))');
    await expect(weightDisplaySection.locator('p')).toContainText(initialWeight);

    // 3. Click the edit button to reveal the input field.
    const editButton = page.getByLabel('Edit weight');
    await editButton.click();

    // 4. Fill in the new target weight.
    const weightInput = page.getByLabel('Edit target weight');
    await expect(weightInput).toBeVisible();
    await weightInput.fill(newWeight);

    // 5. Click the save button to apply the change.
    const saveButton = page.getByLabel('Save weight');
    await saveButton.click();

    // 6. Verify that a success toast notification appears.
    await expect(page.locator('div[role="status"]').getByText('Target Weight Updated')).toBeVisible();

    // 7. Verify that the weight display has been updated with the new weight.
    await expect(weightDisplaySection.locator('p')).toContainText(newWeight);
    
    // 8. Verify the input field is no longer visible after saving.
    await expect(weightInput).not.toBeVisible();

    // 9. Verify that the exercise log was reset by checking if the first rep input is empty.
    const firstRepInput = page.locator('#set-1-reps');
    await expect(firstRepInput).toHaveValue('');

    // 10. Bonus: Confirm logging works after the weight change.
    await firstRepInput.fill('10');
    await page.getByRole('button', { name: 'Log' }).first().click();
    
    // Check that the set was logged with the new details.
    const loggedSetInfo = page.locator('div:has-text("Set 1:")').first();
    await expect(loggedSetInfo).toContainText('Logged: 10 reps');
  });
});
