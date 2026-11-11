<?php

declare(strict_types=1);

use App\Models\User;
use Illuminate\Support\Facades\Hash;

function registrationPayload(array $overrides = []): array
{
    return array_merge([
        'name' => 'Ada Lovelace',
        'email' => 'ada@example.com',
        'password' => 'secret-password',
        'password_confirmation' => 'secret-password',
    ], $overrides);
}

test('a user can register and receives a working API token', function () {
    $response = $this->postJson('/api/register', registrationPayload());

    $response->assertOk()
        ->assertJson(['success' => true])
        ->assertJsonStructure(['success', 'token']);

    $user = User::where('email', 'ada@example.com')->sole();
    expect($user->name)->toBe('Ada Lovelace')
        ->and(Hash::check('secret-password', $user->password))->toBeTrue()
        ->and($user->tokens)->toHaveCount(1);

    $this->withToken($response->json('token'))
        ->getJson('/api/user')
        ->assertOk()
        ->assertJsonPath('email', 'ada@example.com');
});

test('the password is stored hashed, never in plain text', function () {
    $this->postJson('/api/register', registrationPayload())->assertOk();

    expect(User::sole()->getRawOriginal('password'))->not->toBe('secret-password');
});

test('registration rejects an email that is already taken', function () {
    User::factory()->create(['email' => 'ada@example.com']);

    $this->postJson('/api/register', registrationPayload())
        ->assertUnprocessable()
        ->assertJsonValidationErrors('email');

    expect(User::count())->toBe(1);
});

test('registration validates its input', function (array $overrides, string $field) {
    $this->postJson('/api/register', registrationPayload($overrides))
        ->assertUnprocessable()
        ->assertJsonValidationErrors($field);

    expect(User::count())->toBe(0);
})->with([
    'missing name' => [['name' => ''], 'name'],
    'invalid email' => [['email' => 'not-an-email'], 'email'],
    'short password' => [['password' => 'short', 'password_confirmation' => 'short'], 'password'],
    'mismatched confirmation' => [['password_confirmation' => 'something-else'], 'password'],
]);

test('the response does not leak the password hash', function () {
    $this->postJson('/api/register', registrationPayload())
        ->assertOk()
        ->assertJsonMissingPath('password')
        ->assertJsonMissingPath('user.password');
});
