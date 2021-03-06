class { 'nubis_apache':
  check_url => '/health',
}

# Add modules
class { 'apache::mod::rewrite': }
class { 'apache::mod::wsgi': }

apache::vhost { $project_name:
    servername                  => false,
    port                        => 80,
    default_vhost               => true,
    docroot                     => "/var/www/${project_name}",
    docroot_owner               => 'root',
    docroot_group               => 'root',
    block                       => ['scm'],

    setenvif                    => [
      'X-Forwarded-Proto https HTTPS=on',
      'Remote_Addr 127\.0\.0\.1 internal',
      'Remote_Addr ^10\. internal',
    ],

    wsgi_process_group          => $project_name,
    wsgi_script_aliases         => { '/' => "/var/www/${project_name}/iplimit.wsgi" },
    wsgi_daemon_process         => $project_name,
    wsgi_daemon_process_options => {
      processes        => 1,
      threads          => 1,
      maximum-requests => 200,
      display-name     => $project_name,
      home             => "/var/www/${project_name}",
    },

    aliases                     => [
      {
        alias => '/health',
        path  => "/var/www/${project_name}/README.md",
      }
    ],
    custom_fragment             => "
      # Don't set default expiry on anything
      ExpiresActive Off

      # Clustered without coordination
      FileETag None

      ${::nubis::apache::sso::custom_fragment}
    ",
    directories                 => [
      {
        'path'      => "/var/www/${project_name}",
        'provider'  => 'directory',
        'auth_type' => 'openid-connect',
        'require'   => 'valid-user',
      },
      {
        'path'      => '/health',
        'provider'  => 'location',
        'auth_type' => 'None',
        'require'   => 'all granted',
      },
      {
        path           => '/json',
        provider       => 'location',
        auth_name      => 'Secret',
        auth_type      => 'Basic',
        auth_require   => 'user json',
        auth_user_file => "/etc/${project_name}.htpasswd",
      },
    ],

    access_log_env_var          => '!internal',
    access_log_format           => '%a %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"',

    headers                     => [
      # Nubis headers
      "set X-Nubis-Version ${project_version}",
      "set X-Nubis-Project ${project_name}",
      "set X-Nubis-Build   ${packer_build_name}",

      # Security Headers
      'set X-Content-Type-Options "nosniff"',
      'set X-XSS-Protection "1; mode=block"',
      'set X-Frame-Options "DENY"',
      'set Strict-Transport-Security "max-age=31536000"',
    ],
    rewrites                    => [
      {
        comment      => 'HTTPS redirect',
        rewrite_cond => ['%{HTTP:X-Forwarded-Proto} =http'],
        rewrite_rule => ['. https://%{HTTP:Host}%{REQUEST_URI} [L,R=permanent]'],
      }
    ]
}
