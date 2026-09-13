<?php

use Inertia\Testing\AssertableInertia as Assert;

test('root renders the landing page with tracking props for the configured project mode', function () {
    config()->set('analytics.mode', 'ctwa');
    config()->set('analytics.payment_mode', 'none');
    $this->get('/')->assertInertia(fn (Assert $page) => $page
        ->component('landing')
        ->where('tracking.pageUrl', '/')
        ->where('tracking.mode', 'ctwa')
        ->where('tracking.paymentMode', 'none'));

    config()->set('analytics.mode', 'form');
    $this->get('/')->assertInertia(fn (Assert $page) => $page
        ->component('landing')
        ->where('tracking.mode', 'form'));
});
