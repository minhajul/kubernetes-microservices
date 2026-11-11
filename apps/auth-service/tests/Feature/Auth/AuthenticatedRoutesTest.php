<?php

declare(strict_types=1);

use App\Models\User;

test('protected routes reject requests without a token', function (string $method, string $uri) {
    $this->json($method, $uri)
        ->assertUnauthorized()
        ->assertJson(['success' => false]);
})->with([
    'current user' => ['GET', '/api/user'],
    'logout' => ['POST', '/api/logout'],
]);

test('protected routes reject an invalid token', function () {
    $this->withToken('1|not-a-real-token')
        ->getJson('/api/user')
        ->assertUnauthorized();
});

test('the current user endpoint returns the token owner without the password hash', function () {
    $user = User::factory()->create();
    $token = $user->createToken('api-token')->plainTextToken;

    $this->withToken($token)
        ->getJson('/api/user')
        ->assertOk()
        ->assertJsonPath('id', $user->id)
        ->assertJsonPath('email', $user->email)
        ->assertJsonMissingPath('password')
        ->assertJsonMissingPath('remember_token');
});

test('logout revokes only the token that was used', function () {
    $user = User::factory()->create();
    $loggedOut = $user->createToken('api-token')->plainTextToken;
    $otherDevice = $user->createToken('api-token')->plainTextToken;

    $this->withToken($loggedOut)
        ->postJson('/api/logout')
        ->assertOk()
        ->assertJson(['success' => true]);

    expect($user->tokens()->count())->toBe(1);

    // The guard caches the resolved user per application instance; reset it so
    // the next requests authenticate from their tokens again.
    $this->app['auth']->forgetGuards();

    $this->withToken($loggedOut)->getJson('/api/user')->assertUnauthorized();

    $this->app['auth']->forgetGuards();

    $this->withToken($otherDevice)->getJson('/api/user')->assertOk();
});

test('the health endpoint used by the Kubernetes probes responds', function () {
    $this->get('/up')->assertOk();
});
