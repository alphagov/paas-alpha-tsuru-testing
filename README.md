Testing framework for Tsuru deployments
=======================================

Acceptance and integration tests for the tsuru deployment.

How to run it
-------------

Based on ruby 2.2.2, it is recommended to use `rbenv` or `rvm`.

Install the dependencies:

```
bundle install
```

integration tests
-----------------

The integration tests are based on an inventory which should be dynamically
generated. You can list all the tests with:

```
rake -T
```

In order to run all:

```
rake integration:all
```

