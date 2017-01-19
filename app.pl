use Mojolicious::Lite;

use Mojo::File 'path';

sub _gpio { return path('/sys/class/gpio') }

sub _pin {
  my $pin = shift;
  $pin // die 'pin is required';
  return _gpio->child("gpio$pin");
}

helper export => sub {
  my ($c, $pin) = @_;
  return if -e _pin($pin);
  _gpio->child('export')->spurt($pin);
};

helper unexport => sub {
  my ($c, $pin) = @_;
  return unless -e _pin($pin);
  _gpio->child('unexport')->spurt($pin);
};

helper mode => sub {
  my ($c, $pin, $set) = @_;
  my $file = _pin($pin)->child('direction');
  $file->spurt($set) if defined $set;
  chomp (my $out = $file->slurp);
  return $out;
};

helper pin => sub {
  my ($c, $pin, $val) = @_;
  my $file = _pin($pin)->child('value');
  $file->spurt($val) if defined $val;
  chomp (my $out = $file->slurp);
  return $out;
};

helper door_state => sub { 0 + ! shift->pin(16) };

# >0 is out
my %pins = (
  6  =>  1,
  16 => -1,
);

# ensure pins are exported correctly
for my $pin (keys %pins) {
  next unless my $mode = $pins{$pin};
  app->export($pin);
  app->mode($pin, $mode > 0 ? 'out' : 'in');
}

my $r = app->routes;

$r->get('/' => 'index');

my $api = $r->any('/api');

my $door = $api->any('/door');

$door->get('/' => sub {
  my $c = shift;
  my $state = $c->door_state ? \1 : \0;
  $c->render(json => { open => $state });
});

my $gpio = $api->any('/gpio');

$gpio->any([qw/GET POST/] => '/:pin' => sub {
  my $c = shift;
  my $pin = $c->stash('pin');
  return $c->reply->not_found unless $pins{$pin};
  if ($c->req->method eq 'POST') {
    $c->pin($pin, $c->req->body);
  }
  $c->render(text => $c->pin($pin));
});

app->start;

__DATA__

@@ index.html.ep

<!DOCTYPE html>
<html>
<head>
  %= stylesheet begin
    #layer2 {
      transition: transform 3.0s ease;
    }
    #layer2.open {
      transform: translateY(-100%);
    }
  % end
</head>
<body>
  <div class="door-holder" onclick="openDoor()"><%== app->home->child(qw/art car.svg/)->slurp %></div>
  <script>
    var door_state = <%= door_state %>;
    document.addEventListener("DOMContentLoaded", function(event) {
      if (!door_state) return;
      document.getElementById('layer2').classList.add('open');
    });
    function openDoor() {
      document.getElementById('layer2').classList.toggle('open');
    }
  </script>
</body>
</html>
