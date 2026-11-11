<?php

declare(strict_types=1);

use App\Models\User;

test('a user can log in with valid credentials and receives a working API token', function () {
    $user = User::factory()->create(['email' => 'ada@example.com']);

    $response = $this->postJson('/api/login', [
        'email' => 'ada@example.com',
        'password' => 'password',
    ]);

    $response->assertOk()
        ->assertJson(['success' => true])
        ->assertJsonStructure(['success', 'token']);

    expect($user->tokens()->count())->toBe(1);

    $this->withToken($response->json('token'))
        ->getJson('/api/user')
        ->assertOk()
        ->assertJsonPath('id', $user->id);
});

test('each login issues a new token', function () {
    $user = User::factory()->create(['email' => 'ada@example.com']);
    $credentials = ['email' => 'ada@example.com', 'password' => 'password'];

    $first = $this->postJson('/api/login', $credentials)->json('token');
    $second = $this->postJson('/api/login', $credentials)->json('token');

    expect($first)->not->toBe($second)
        ->and($user->tokens()->count())->toBe(2);
});

test('login fails with a wrong password', function () {
    User::factory()->create(['email' => 'ada@example.com']);

    $this->postJson('/api/login', [
        'email' => 'ada@example.com',
        'password' => 'wrong-password',
    ])
        ->assertUnprocessable()
        ->assertJsonValidationErrors(['email' => 'Invalid credentials'])
        ->assertJsonMissingPath('token');
});

test('login fails for an unknown email with the same message as a wrong password', function () {
    $this->postJson('/api/login', [
        'email' => 'nobody@example.com',
        'password' => 'password',
    ])
        ->assertUnprocessable()
        ->assertJsonValidationErrors(['email' => 'Invalid credentials']);
});

test('login validates its input', function (array $payload, string $field) {
    $this->postJson('/api/login', $payload)
        ->assertUnprocessable()
        ->assertJsonValidationErrors($field);
})->with([
    'missing email' => [['password' => 'password'], 'email'],
    'invalid email' => [['email' => 'not-an-email', 'password' => 'password'], 'email'],
    'missing password' => [['email' => 'ada@example.com'], 'password'],
]);
