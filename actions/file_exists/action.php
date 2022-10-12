<?php // phpcs:disable
$output = getenv('GITHUB_OUTPUT') || '';
$paths = explode(' ', getenv('INPUT_PATHS')) ?? [];
$convertedValue = json_encode(array_sum(array_map(file_exists(...), $paths)) > 0);
if (file_exists($output)) {
    $delimiter = 'ghadelimiter_' . hash('sha256', date('YmdHis'));
    file_put_contents($output, "file_exists<<{$delimiter}\n{$convertedValue}\n{$delimiter}");
} else {
    echo "::set-output name=file_exists::{$convertedValue}\n";
}
